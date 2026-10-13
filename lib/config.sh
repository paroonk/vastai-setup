# Paths, env-var defaults and the (empty) install lists. Sourced by provision.sh.
# WORKSPACE, SETUP_REPO, SETUP_REF and REPO_DIR are set by provision.sh before this runs.

COMFY="${WORKSPACE}/ComfyUI"
M="${COMFY}/models"
FAILED=()

STACKS="${STACKS:-all}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"
SELECTED=()   # stacks actually loaded

# The install lists. Empty here; lib/base.sh fills in the base entries, then stacks and families only append (+=).
APT_PACKAGES=()
PIP_PACKAGES=()   # each entry is passed to pip unquoted, so an entry may carry its own flags
NODES=()
MODELS=()     # "subdir|url" or "subdir|url|filename"
CIVITAI=()    # "target|url" or "target|url|filename"
LINKS=()      # "link|target", both relative to models/: expose one downloaded file at a second path
WF_SUBST=()   # "from|to": text replaced in installed workflow JSONs (e.g. a model filename swapped for the file actually downloaded)
