#!/usr/bin/env python

import os, sys, time, socket, traceback, syslog, json, argparse

log_f = os.fdopen(os.dup(sys.stdout.fileno()), "aw")
pid = None
use_syslog = False

def reopenlog(log_file):
    global log_f
    if log_f:
        log_f.close()
    if log_file and log_file <> "stdout:":
        log_f = open(log_file, "aw")
    elif log_file and log_file == "stdout:":
        log_f = os.fdopen(os.dup(sys.stdout.fileno()), "aw")

def log(txt):
    global log_f, pid, use_syslog
    if use_syslog:
        syslog.syslog(txt)
        return
    if not pid:
        pid = os.getpid()
    t = time.strftime("%Y%m%dT%H:%M:%SZ", time.gmtime())
    print >>log_f, "%s [%d] %s" % (t, pid, txt)
    log_f.flush()

def success(result):
    return { "Status": "Success", "Value": result }

def handle_exception(e, code = None, params = None):
    s = sys.exc_info()
    files = []
    lines = []
    for slot in traceback.extract_tb(s[2]):
        files.append(slot[0])
        lines.append(slot[1])
    backtrace = {
      "error": str(s[1]),
      "files": files,
      "lines": lines,
    }
    code = "SR_BACKEND_FAILURE"
    params = [ str(s[1]) ]
    if hasattr(e, "code"):
      code = e.code
    if hasattr(e, "params"):
      params = e.params
    results = {
      "code": code,
      "params": params,
      "backtrace": backtrace,
    }
    print >>sys.stdout, json.dumps(results)
    sys.exit(1)

class XenAPIException(Exception):
    def __init__(self, code, params):
        Exception.__init__(self)
        if type(code) <> type("") and type(code) <> type(u""):
            raise (TypeError("string", repr(code)))
        if type(params) <> type([]):
            raise (TypeError("list", repr(params)))
        self.code = code
        self.params = params

class MissingDependency(Exception):
    def __init__(self, missing):
        self.missing = missing
    def __str__(self):
        return "There is a missing dependency: %s not found" % self.missing

class Rpc_light_failure(Exception):
    def __init__(self, name, args):
        self.name = name
        self.args = args
    def failure(self):
        # rpc-light marshals a single result differently to a list of results
        args = list(self.args)
        marshalled_args = args
        if len(args) == 1:
            marshalled_args = args[0]
        return { 'Status': 'Failure',
                 'ErrorDescription': [ self.name, marshalled_args ] }

class InternalError(Rpc_light_failure):
    def __init__(self, error):
        Rpc_light_failure.__init__(self, "Internal_error", [ error ])

class UnmarshalException(InternalError):
    def __init__(self, thing, ty, desc):
        InternalError.__init__(self, "UnmarshalException thing=%s ty=%s desc=%s" % (thing, ty, desc))

class TypeError(InternalError):
    def __init__(self, expected, actual):
        InternalError.__init__(self, "TypeError expected=%s actual=%s" % (expected, actual))

class UnknownMethod(InternalError):
    def __init__(self, name):
        InternalError.__init__(self, "Unknown method %s" % name)


def is_long(x):
    try:
        long(x)
        return True
    except:
        return False

class ListAction(argparse.Action):
    def __call__(self, parser, namespace, values, option_string=None):
        k = values[0]
        v = values[1]
        if hasattr(namespace, self.dest) and getattr(namespace, self.dest) is not None:
            getattr(namespace, self.dest)[k] = v
        else:
            setattr(namespace, self.dest, { k: v })

# Well-known feature flags understood by xapi ##############################
# XXX: add an enum to the IDL?

feature_sr_probe = "SR_PROBE"
feature_sr_update = "SR_UPDATE"
feature_sr_supports_local_caching = "SR_SUPPORTS_LOCAL_CACHING"
feature_vdi_create = "VDI_CREATE"
feature_vdi_delete = "VDI_DELETE"
feature_vdi_attach = "VDI_ATTACH"
feature_vdi_detach = "VDI_DETACH"
feature_vdi_resize = "VDI_RESIZE"
feature_vdi_resize_online = "VDI_RESIZE_ONLINE"
feature_vdi_clone = "VDI_CLONE"
feature_vdi_snapshot = "VDI_SNAPSHOT"
feature_vdi_activate = "VDI_ACTIVATE"
feature_vdi_deactivate = "VDI_DEACTIVATE"
feature_vdi_update = "VDI_UPDATE"
feature_vdi_introduce = "VDI_INTRODUCE"
feature_vdi_generate_config = "VDI_GENERATE_CONFIG"
feature_vdi_reset_on_boot = "VDI_RESET_ON_BOOT"
