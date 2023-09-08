#!/usr/bin/env python

# Wrapper around single-shot resource attach/detach scripts.
#
# The 'resource' interface allows storage and networks to be attached
# and detached by single-shot scripts. All operations are asynchronous,
# 'attach' and 'detach' return a 'task' object which has a 'cancel'
# operation. When 'cancel' is called, the running subprocesses are
# first sent SIGTERM and then SIGKILL.

import syslog
import threading
import time
import getopt 
import sys
import subprocess
import gtk
import gobject
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop

my_name = "dbus-resource-script"

name = None
script = None
debug_on = False
def debug(message):
  if debug_on:
    print "DEBUG: ", message
    sys.stdout.flush()

syslog.openlog(my_name)
def info(message):
  if debug_on:
    print "INFO: ", message
    sys.stdout.flush()
  syslog.syslog(message)
def error(message):
  if debug_on:
    print "ERROR: ", message
    sys.stdout.flush()
  syslog.syslog(syslog.LOG_ERR, message)

try:
  opts, args = getopt.getopt(sys.argv[1:],"dhn:c:s:",["debug","name=","script="])
except getopt.GetoptError:
  print '%s -n <object> -s <script>' % my_name
  sys.exit(2)
for opt, arg in opts:
  if opt in ("-d", "--debug"):
    debug_on = True
  elif opt == '-h':
    print '%s -n <object> -s <script>' % my_name
    sys.exit()
  elif opt in ("-n", "--name"):
    name = arg
  elif opt in ("-s", "--script"):
    script = arg

if not(name):
  print "Please supply a bus name argument (-n or --name=)"
  sys.exit(2)
if not(script):
  print "Please supply a script name argument (-s or --script="
  sys.exit(2)

next_task_id = 0

TASK_INTERFACE="org.xenserver.api.task"

class Canceller(threading.Thread):
    """A thread which attempts to cleanly shutdown a process, resorting
       to SIGKILL if it fails to respond after a timeout"""
    def __init__(self, process, dbus_object):
        threading.Thread.__init__(self)
        self.process = process
        self.dbus_object = dbus_object
        self.start()
    def run(self):
        info("%s: cancelling: sending SIGTERM to %d" % (self.dbus_object.path, self.process.pid))
        try:
            self.process.terminate()
        except:
            pass
        for i in range(0, 60):
            if self.process.poll() <> None:
                continue
            sys.stdout.flush()
            time.sleep(1)
        if self.process.poll() <> None:
            info("%s: cancelling: sending SIGKILL to %d" % (self.dbus_object.path, self.process.pid))
            try:
                self.process.kill()
            except:
                pass
        try: 
            self.process.wait()
        except:
            pass
        info("%s: cancelling: deleting object" % self.dbus_object.path)
        self.dbus_object.remove_from_connection()


class Task(dbus.service.Object, threading.Thread):
    def __init__(self, cmd):
        threading.Thread.__init__(self)

        self.bus = dbus.SessionBus()
        bus_name = dbus.service.BusName(name, bus=self.bus)

        global next_task_id
        self.task_id = next_task_id
        next_task_id = next_task_id + 1
        self.path = "/org/xenserver/task/" + str(self.task_id)
        self.completed = False
        self.canceller = None
        self.result = None

        try:
            self.process = subprocess.Popen(cmd, stdout=subprocess.PIPE)
        except Exception, e:
            error("%s: %s" % (" ".join(cmd), str(e)))
            raise dbus.exceptions.DBusException(
               'org.xenserver.UnknownException',
               'An exception was caught while running %s' % (" ".join(cmd)))

        dbus.service.Object.__init__(self, bus_name, self.path)

        info("%s: running %s" % (self.path, " ".join(cmd)))
        self.start()

    def run(self):
        stdout, stderr = self.process.communicate()
        self.completed = True
        self.result = stdout
        info("%s: completed with returncode %d" % (self.path, self.process.returncode))

    @dbus.service.method(dbus_interface=TASK_INTERFACE)
    def cancel(self):
        if self.canceller == None:
            self.canceller = Canceller(self.process, self)
        else:
            info("%s: cancel: already cancelling, ignoring request" % self.path)
        # the canceller will terminate the subprocess and
        # remove this object from the bus

    @dbus.service.method(dbus_interface=TASK_INTERFACE)
    def destroy(self):
        if self.canceller <> None:
            info("%s: destroy: task is being cancelled already" % self.path)
            # canceller will clean up
            return
        if self.completed:
            info("%s: destroy: task complete, removing object" % self.path)
            self.remove_from_connection()
            return
        info("%s: destroy: task is running, requesting cancel" % self.path)
        self.cancel()

    @dbus.service.method(dbus_interface=TASK_INTERFACE)
    def getResult(self):
        if self.result:
            return self.result
        else:
            error("%s: TaskNotFinished" % self.path)
            raise dbus.exceptions.DBusException(
                'org.xenserver.api.TaskNotFinished',
                'The task is still running.')

    @dbus.service.method(dbus_interface=dbus.PROPERTIES_IFACE, in_signature='ss', out_signature='v')
    def Get(self, interface_name, property_name):
        return self.GetAll(interface_name)[property_name]

    @dbus.service.method(dbus_interface=dbus.PROPERTIES_IFACE, in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface_name):
        if interface_name == TASK_INTERFACE:
            return { 'completed': self.completed,
                     'cancelling': self.canceller <> None }
        else:
            raise dbus.exceptions.DBusException(
                'com.example.UnknownInterface',
                'The Foo object does not implement the %s interface'
                    % interface_name)

RESOURCE_INTERFACE="org.xenserver.api.resource"

class Resource(dbus.service.Object):
    def __init__(self):
        self.bus = dbus.SessionBus()
        bus_name = dbus.service.BusName(name, bus=self.bus)
        dbus.service.Object.__init__(self, bus_name, "/" + name.replace(".", "/"))

    @dbus.service.method(dbus_interface=RESOURCE_INTERFACE, in_signature="s", out_signature="o")
    def attach(self, global_uri):
        return Task([script, "attach", global_uri]).path
    @dbus.service.method(dbus_interface=RESOURCE_INTERFACE, in_signature="s", out_signature="")
    def detach(self, id):
        return Task([script, "detach", id]).path

gobject.threads_init()
DBusGMainLoop(set_as_default=True)
resource = Resource()
gtk.main()
