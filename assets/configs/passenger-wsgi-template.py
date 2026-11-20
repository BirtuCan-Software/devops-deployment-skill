# ==============================================================================
# Universal Hardened passenger_wsgi.py for cPanel Phusion Passenger
# Solves: Virtualenv path discovery, site-packages registration (.pth processing),
#         LiteSpeed startup crashes, and disguised "CORS" errors caused by 500s.
# ==============================================================================
import os
import sys
import glob
import site
from pathlib import Path

# 1. Enforce Application Root & Working Directory
# This guarantees that .env files and relative imports are correctly resolved by
# python-decouple, django-environ, and framework components.
APP_ROOT = Path(__file__).resolve().parent
os.chdir(str(APP_ROOT))
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

# 2. Virtual Environment Auto-Discovery
def discover_virtualenv():
    # A. Active environment variable check
    if os.environ.get("VIRTUAL_ENV"):
        venv_path = Path(os.environ["VIRTUAL_ENV"])
        if (venv_path / "bin" / "activate").is_file():
            return venv_path

    home = Path.home()
    app_name = APP_ROOT.name

    # B. CloudLinux / cPanel Python Selector path:
    # Standard location: ~/virtualenv/<app_dir_or_name>/<python_version>/
    cpanel_venv_root = home / "virtualenv"
    if cpanel_venv_root.is_dir():
        # Match exact application directory name first
        matched = list(cpanel_venv_root.glob(f"{app_name}/*"))
        for candidate in matched:
            if (candidate / "bin" / "activate").is_file():
                return candidate

        # Fuzzy match (case-insensitive)
        for candidate in cpanel_venv_root.glob("*/*"):
            if app_name.lower() in str(candidate).lower() and (candidate / "bin" / "activate").is_file():
                return candidate

        # Fallback to any valid virtualenv under ~/virtualenv/
        for candidate in cpanel_venv_root.glob("*/*"):
            if (candidate / "bin" / "activate").is_file():
                return candidate

    # C. In-project virtual environment fallback (.venv, venv, env)
    for folder in [".venv", "venv", "env"]:
        local_venv = APP_ROOT / folder
        if (local_venv / "bin" / "activate").is_file():
            return local_venv

    return None

VENV_PATH = discover_virtualenv()

if VENV_PATH:
    # 3. Execute activate_this.py if present
    activate_this = VENV_PATH / "bin" / "activate_this.py"
    if activate_this.is_file():
        with open(activate_this) as f:
            exec(f.read(), {"__file__": str(activate_this)})

    # 4. Register all site-packages (both lib and lib64) using site.addsitedir()
    # site.addsitedir() is required instead of sys.path.append() to properly process
    # .pth files, namespace packages, and egg-links.
    for sp_path in glob.glob(str(VENV_PATH / "lib*" / "python*" / "site-packages")):
        if os.path.isdir(sp_path):
            site.addsitedir(sp_path)

    # 5. Place virtualenv binary directory on PATH for subprocesses
    venv_bin = str(VENV_PATH / "bin")
    if venv_bin not in os.environ.get("PATH", ""):
        os.environ["PATH"] = f"{venv_bin}:{os.environ.get('PATH', '')}"

# 6. Database Driver Workaround for Shared Hosting (PyMySQL -> MySQLdb)
try:
    import pymysql
    pymysql.install_as_MySQLdb()
except ImportError:
    pass

# 7. WSGI Application Loading & Dispatch
def load_application():
    # A. Check if WSGI module is defined via environment variable
    custom_wsgi = os.environ.get("WSGI_APPLICATION")
    if custom_wsgi:
        try:
            mod_path, app_name = custom_wsgi.rsplit(".", 1)
            mod = __import__(mod_path, fromlist=[app_name])
            return getattr(mod, app_name)
        except Exception:
            pass

    # B. Common Django WSGI modules
    common_django_modules = [
        "backend_config.wsgi",
        "config.wsgi",
        "core.wsgi",
        f"{APP_ROOT.name}.wsgi",
    ]
    for mod_name in common_django_modules:
        try:
            mod = __import__(mod_name, fromlist=["application"])
            if hasattr(mod, "application"):
                return getattr(mod, "application")
        except ImportError:
            pass

    # C. Dynamic search for any */wsgi.py
    for wsgi_file in APP_ROOT.glob("*/wsgi.py"):
        pkg = wsgi_file.parent.name
        try:
            mod = __import__(f"{pkg}.wsgi", fromlist=["application"])
            if hasattr(mod, "application"):
                return getattr(mod, "application")
        except Exception:
            pass

    # D. FastAPI / Flask / ASGI fallback (main.py, app.py)
    for mod_name in ["main", "app", "api"]:
        try:
            mod = __import__(mod_name, fromlist=["app", "application"])
            if hasattr(mod, "application"):
                return getattr(mod, "application")
            elif hasattr(mod, "app"):
                app_obj = getattr(mod, "app")
                # Wrap ASGI app (e.g. FastAPI) with a2wsgi if available
                if hasattr(app_obj, "__call__") and not hasattr(app_obj, "wsgi_app"):
                    try:
                        from a2wsgi import ASGIMiddleware
                        return ASGIMiddleware(app_obj)
                    except ImportError:
                        return app_obj
                return app_obj
        except ImportError:
            pass

    raise RuntimeError(
        "Could not automatically locate a WSGI 'application' in the project root. "
        "Ensure your Django wsgi.py is present or set WSGI_APPLICATION in your environment."
    )

application = load_application()
