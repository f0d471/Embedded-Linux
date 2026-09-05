#include "common.h"

const char *err_str(int err)
{
	switch (err) {
	case ERR_OK:       return "ok";
	case ERR_PARAM:    return "invalid parameter";
	case ERR_NOMEM:    return "out of memory";
	case ERR_IO:       return "device io failed";
	case ERR_NOTSUP:   return "not supported";
	case ERR_NOTFOUND: return "not found";
	case ERR_BUSY:     return "busy";
	default:           return "unknown error";
	}
}
