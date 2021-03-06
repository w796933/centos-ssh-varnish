# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
readonly SERVICE_UNIT_ENVIRONMENT_KEYS="
 DOCKER_CONTAINER_OPTS
 DOCKER_IMAGE_PACKAGE_PATH
 DOCKER_IMAGE_TAG
 DOCKER_PORT_MAP_TCP_80
 DOCKER_PORT_MAP_TCP_8443
 ULIMIT_MEMLOCK
 ULIMIT_NOFILE
 ULIMIT_NPROC
 VARNISH_MAX_THREADS
 VARNISH_MIN_THREADS
 VARNISH_STORAGE
 VARNISH_THREAD_TIMEOUT
 VARNISH_TTL
 VARNISH_VCL_CONF
"

readonly SERVICE_UNIT_REGISTER_ENVIRONMENT_KEYS="
 REGISTER_ETCD_PARAMETERS
 REGISTER_TTL
 REGISTER_UPDATE_INTERVAL
"

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
SERVICE_UNIT_INSTALL_TIMEOUT=${SERVICE_UNIT_INSTALL_TIMEOUT:-5}
