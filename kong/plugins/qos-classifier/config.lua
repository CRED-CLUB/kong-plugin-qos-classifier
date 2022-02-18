local _M = {}

-- TTL value of counters which keep the number of requests in a window
_M.COUNTER_TTL_IN_SECS = 5

-- sync interval for counters to lua shared dict
_M.COUNTER_SYNC_INTERVAL = 1

-- name of the lua shared dict, for counters, as defined in nginx config
_M.QOS_SHARED_DICT = "qos_shared"

-- name of the lua shared dict, for resty locks, as defined in nginx config
_M.QOS_SHARED_LOCK = "qos_lock"

return _M
