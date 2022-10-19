#!/usr/bin/env python
#
# Copyright (C) Citrix Inc
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

# Example storage backend using SMAPIv2

# WARNING: this API is considered to be unstable and may be changed at-will

import os, sys, commands, xmlrpclib

import xcp
from storage import *

import vhd, tapdisk, mount, util

# The on-disk structure looks like this:
# 
# <root>/metadata/hostname.name.xml    -- VDI metadata for a disk with name "name"
# <root>/metadata/hostname.name.1.xml  -- VDI metadata for another disk with name "name"
#
# <root>/data/hostname.1.vhd  -- vhd format disk (parent or leaf)
# <root>/data/hostname.2.vhd  -- vhd format disk (parent or leaf)
# <root>/data/hostname.3.raw  -- raw format disk
#
# where "hostname" is a prefix unique to this instance which prevents accidental
# filename clashes.
# 
# There is an injective relationship between metadata/ files and data/
# i.e. all metadata/ files reference exactly one data/ file but not all
# data/ files are referenced directly by a metadata/ file.

raw_suffix = ".raw"
vhd_suffix = ".vhd"
metadata_suffix = ".xml"

metadata_dir = "metadata"
data_dir = "data"

repo_state_dir = "/tmp/repo-state"

def unlink_safe(path):
    try:
        os.unlink(path)
        log("os.unlink %s OK" % path)
    except Exception, e:
        log("os.unlink %s: %s" % (path, str(e)))

def highest_id(xs):
    highest = 0L
    for x in xs:
        try:
            y = long(x)
            if y > highest:
                highest = y
        except:
            pass
    return highest

def make_fresh_metadata_name(root, prefix, name):
    """Make a human-readable name for on-disk metadata, using a prefix unique
    to this instance to guarantee no clashes"""
    # To make this vaguely human-readable, sanitise the first 32 chars of the
    # VDI's name and then add a numerical suffix to make unique.
    if len(name) > 32:
        # arbitrary cut-off
        name = name[0:32]
    valid = '_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    name = ''.join(c for c in name if c in valid)
    if name == "":
        name = "_"
    taken = map(lambda x:x[0:-len(metadata_suffix)], os.listdir(root + "/" + metadata_dir))
    if name not in taken:
        return name
    else:
        superstrings = filter(lambda x:x.startswith(name + "."), taken)
        suffixes = map(lambda x:x[len(name) + 1:], superstrings)
        suffix = highest_id(suffixes) + 1L
        return "%s.%Ld" % (name, suffix)

def metadata_path(root, key):
    return root + "/" + metadata_dir + "/" + key + metadata_suffix

def loads(path):
    try:
        f = open(path, "r")
    except:
        log("%s does not exist: returning None" % path)
        return None
    try:
        try:
            return xmlrpclib.loads(f.read())[0][0]
        except:
            log("%s is corrupt: returning None" % path)
    finally:
        f.close()

def dumps(path, x):
    f = open(path, "w")
    try:
        try:
            f.write(xmlrpclib.dumps((x,), allow_none=True))
        except Exception, e:
            log("Exception writing metadata: %s" % (str(e)))
            # remove corrupt file
            os.unlink(path)
    finally:
        f.close()

def write_metadata(root, name, vdi_info):
    dumps(metadata_path(root, name), vdi_info)

def write_repo_state(sr, info):
    dumps(repo_state_dir + "/" + sr, info)

def read_metadata(root, name):
    """Read the vdi_info metadata associated with 'name', throwing Vdi_does_not_exist if
    it cannot be read."""
    md = metadata_path(root, name)
    result = loads(md)
    if not result:
        raise Vdi_does_not_exist(name)
    return result

def list_repo_state():
    return os.listdir(repo_state_dir)

def read_repo_state(sr):
    return loads(repo_state_dir + "/" + sr)

def delete_repo_state(sr):
    os.unlink(repo_state_dir + "/" + sr)

def list_metadata(root):
    results = []
    metadata_path = root + "/" + metadata_dir
    for name in os.listdir(metadata_path):
        if name.endswith(metadata_suffix):
            name = name[0:-len(metadata_suffix)]
            results.append(name)
    return results

def read_all_metadata(root):
    results = {}
    for name in list_metadata(root):
        vdi_info = read_metadata(root, name)
        if vdi_info:
            results[name] = vdi_info
    return results

def read_tree(root):
    results = {}
    data_path = root + "/" + data_dir
    for name in os.listdir(data_path):
        if name.endswith(raw_suffix):
            results[name[0:-len(raw_suffix)]] = { "type": "raw" }
    all = vhd.list(data_path + "/*.vhd")
    for name in all.keys():
        log("data[%s] = %s" % (name, repr(all[name])))
        results[name] = all[name]
    return results

def get_deletable(root):
    """Return a set of the data blobs which are not reachable from
    any of the VDIs """
    reachable = set()
    data = read_tree(root)
    for vdi_info in read_all_metadata(root).values():
        x = vdi_info["data"]
        while x not in reachable:
            reachable.add(x)
            info = data[x]
            if "parent" in info:
                x = info["parent"]
    all = set(data.keys())
    return all.difference(reachable)

def read_data(root, key):
    base = root + "/" + data_dir + "/" + key
    raw_path = base + raw_suffix
    vhd_path = base + vhd_suffix
    if os.path.exists(raw_path):
        return { "type": "raw", "path": raw_path }
    if os.path.exists(vhd_path):
        one_vhd = vhd.list(vhd_path).values()[0]
        one_vhd["path"] = vhd_path
        return one_vhd
    raise (Vdi_does_not_exist(key))

def data_path(root, key):
    return read_data(root, key)["path"]

def data_type(root, key):
    return read_data(root, key)["type"]

def gc(root):
    deletable = get_deletable(root)
    for x in deletable:
        log("Data %s is unreachable now" % x)
        path = data_path(root, x)
        unlink_safe(path)

def get_my_highest_id(root, prefix):
    data_path = root + "/" + data_dir
    xs = []
    for x in os.listdir(data_path):
        if not(x.startswith(prefix)):
            break
        x = x[len(prefix):]
        if x.endswith(raw_suffix):
            x = x[0:-len(raw_suffix)]
        if x.endswith(vhd_suffix):
            x = x[0:-len(vhd_suffix)]
        xs.append(x)

    return highest_id(xs)

def list_tapdisks():
    results = {}
    for tap in tapdisk.list():
        if not tap.file:
            log("%s has no file open: detaching and freeing" % str(tap))
            tap.detach()
            tap.free()
        else:
            ty, path = tap.file
            if path.startswith(data_path):
                filename = os.path.basename(path)
                if ty == "raw":
                    name = filename[0:-len(raw_suffix)]
                    log("%s open by %s" % (name, str(tap)))
                    results[name] = tap
                elif ty == "vhd":
                    name = filename[0:-len(vhd_suffix)]
                    log("%s open by %s" % (name, str(tap)))
                    results[name] = tap
                else:
                    log("Unknown tapdisk type: %s" % ty)
    return results

class Repo:
    """Encapsulates all relevant SR operations"""
    def __init__(self, hostname, path):
        self.hostname = hostname
        self.path = path

        # Make sure necessary paths exist
        metadata_path = path + "/" + metadata_dir
        if not (os.path.exists(metadata_path)):
            os.mkdir(metadata_path)
        data_path = path + "/" + data_dir
        if not(os.path.exists(data_path)):
            os.mkdir(data_path)

        # Non-shared state is cached:
        self.writable = {} # activated read/write (XXX persistence)
        self.tapdisks = list_tapdisks()

        # Non-shared counter used to avoid name collisions when making vhds
        self._data_highest_id = get_my_highest_id(path, hostname) + 1L

    def scan(self):
        return read_all_metadata(self.path).values()

    def make_fresh_data_name(self):
        name = str(self._data_highest_id)
        self._data_highest_id = self._data_highest_id + 1
        return self.hostname + "." + name

    def create(self, vdi_info):
        vdi = make_fresh_metadata_name(self.path, self.hostname, vdi_info["name_label"])
        vdi_info["vdi"] = vdi

        data = self.make_fresh_data_name()
        vdi_info["data"] = data

        stem = self.path + "/" + data_dir + "/" + data
        virtual_size = long(vdi_info["virtual_size"])
        sm_config = vdi_info["sm_config"]
        if "type" in sm_config and sm_config["type"] == "raw":
            f = open(stem + raw_suffix, "wc")
            try:
                f.truncate(virtual_size)
            finally:
                f.close()
        else:
            # xmlrpclib will reject longs which are > 32 bits since it will try
            # to marshal them as XMLRPC integers.
            vdi_info["virtual_size"] = str(vhd.create(virtual_size, stem + vhd_suffix))

        write_metadata(self.path, vdi, vdi_info)
        return vdi_info

    def destroy(self, vdi):
        meta = metadata_path(self.path, vdi)
        unlink_safe(meta)
        gc(self.path)

    def clone(self, vdi, vdi_info):
        meta = read_metadata(self.path, vdi)
        parent = data_path(self.path, meta["data"])

        # Create two vhd leaves whose parent is [vdi]
        left = self.make_fresh_data_name()
        vhd.make_leaf(self.path + "/" + data_dir + "/" + left + vhd_suffix, parent)

        right = self.make_fresh_data_name()
        vhd.make_leaf(self.path + "/" + data_dir + "/" + right + vhd_suffix, parent)

        # Remap the original [vdi]'s location to point to the first leaf's path
        parent_info = read_metadata(self.path, vdi)
        parent_info["data"] = left
        write_metadata(self.path, vdi, parent_info)

        # The cloned vdi's location points to the second leaf's path
        clone = make_fresh_metadata_name(self.path, self.hostname, vdi_info["name_label"])
        vdi_info["vdi"] = clone
        vdi_info["data"] = right
        vdi_info["virtual_size"] = parent_info["virtual_size"]
        vdi_info["content_id"] = parent_info["content_id"]
        if vdi_info["content_id"] == "":
            vdi_info["content_id"] = util.gen_uuid()
        vdi_info["read_only"] = parent_info["read_only"]
        write_metadata(self.path, clone, vdi_info)

        return vdi_info

    def snapshot(self, vdi, vdi_info):
        # Before modifying the vhd-tree, take a note of the
        # currently-active leaf so we can find its tapdisk later
        old_leaf = read_metadata(self.path, vdi)["data"]

        # The vhd-tree manipulation is the same as clone...
        vdi_info = self.clone(vdi, vdi_info)
        vdi_info["snapshot_of"] = vdi
        # XXX vdi_info["snapshot_time"]
        # ... but we also re-open any active tapdisks
        if old_leaf in self.tapdisks:
            sm_config = vdi_info["sm_config"]
            tapdisk = self.tapdisks[old_leaf]
            if "mirror" in sm_config:
                tapdisk.mirror = sm_config["mirror"]
            else:
                tapdisk.mirror = None
            # Find the new vhd leaf
            new_leaf = read_metadata(self.path, vdi)["data"]

            tapdisk.file = (data_type(self.path, new_leaf), data_path(self.path, new_leaf))
            tapdisk.reopen()
            del self.tapdisks[old_leaf]
            self.tapdisks[new_leaf] = tapdisk
        return vdi_info

    def stat(self, vdi):
        return read_metadata(self.path, vdi)

    def set_persistent(self, vdi, persistent):
        meta = read_metadata(self.path, vdi)

        if meta["persistent"] and not persistent:
            # We need to make a fresh vhd leaf
            parent = data_path(self.path, meta["data"])

            leaf = self.make_fresh_data_name()
            vhd.make_leaf(self.path + "/" + data_dir + "/" + leaf + vhd_suffix, parent)

            # Remap the original [vdi]'s location to point to the new leaf
            meta["data"] = leaf

        meta["persistent"] = persistent
        write_metadata(self.path, vdi, meta)

    def set_content_id(self, vdi, content_id):
        meta = read_metadata(self.path, vdi)
        meta["content_id"] = content_id
        write_metadata(self.path, vdi, meta)

    def get_by_name(self, name):
        meta = read_metadata(self.path, name)
        if not meta:
            raise Vdi_does_not_exist(name)
        return meta

    def similar_content(self, vdi):
        chains = {}
        metadata = read_all_metadata(self.path)
        tree = read_tree(self.path)
        if vdi not in metadata.keys():
            raise Vdi_does_not_exist(vdi)
        for v in metadata.keys():
            md = metadata[v]
            data = md["data"]
            chain = set([data])
            while "parent" in tree[data]:
                data = tree[data]["parent"]
                chain.add(data)
            chains[v] = chain
        distance = {}
        target_chain = chains[vdi]
        for v in metadata.keys():
            this_chain = chains[v]
            difference = target_chain.symmetric_difference(this_chain)
            # if two disks have nothing in common then we don't consider them
            # as similar at all
            if target_chain.intersection(this_chain) <> set([]):
                distance[v] = len(difference)
        import operator
        ordered = sorted(distance.iteritems(), key=operator.itemgetter(1))
        return map(lambda x:metadata[x[0]], ordered)

    def maybe_reset(self, vdi):
        meta = read_metadata(self.path, vdi)
        if not(meta["persistent"]):
            # we throw away updates to the leaf
            leaf = meta["data"]
            leaf_info = read_data(self.path, vdi)
            new_leaf = self.make_fresh_data_name()

            if "parent" in leaf_info:
                # Create a new leaf
                child = self.path + "/" + data_dir + "/" + new_leaf + vhd_suffix
                parent = self.path + "/" + data_dir + "/" + leaf_info["parent"] + vhd_suffix
                vhd.make_leaf(child, parent)
                meta["data"] = new_leaf
                write_metadata(self.path, vdi, meta)
                gc(self.path)
            else:
                # Recreate a whole blank disk
                new_info = self.create(meta, leaf_info)
                meta["data"] = new_info["data"]
                write_metadata(self.path, vdi, meta)
                self.destroy(new_info["vdi"])

    def epoch_begin(self, vdi):
        self.maybe_reset(vdi)

    def epoch_end(self, vdi):
        self.maybe_reset(vdi)

    def open_dummy_vhd(self, vdi_info, tapdisk):
        # blkback will immediately close if it encounters a blktap
        # device which doesn't have a backing file. It probably needs
        # to know the number of sectors? We can satisfy this with a
        # temporary .vhd file
        dummy_data_name = self.make_fresh_data_name()
        dummy_path = self.path + "/" + data_dir + "/" + dummy_data_name + ".dummy" + vhd_suffix
        virtual_size = long(vdi_info["virtual_size"])
        vhd.create(virtual_size, dummy_path)
        tapdisk.open("vhd", dummy_path)
        os.unlink(dummy_path)

    def attach(self, vdi, read_write):
        md = read_metadata(self.path, vdi)
        data = md["data"]
        if data in self.tapdisks:
            raise Backend_error("VDI_ALREADY_ATTACHED", [ vdi ])
        self.tapdisks[data] = tapdisk.Tapdisk()
        device = self.tapdisks[data].get_device()
        self.writable[vdi] = read_write

        self.open_dummy_vhd(md, self.tapdisks[data])

        return { "params": device,
                 "xenstore_data": {} }

    def activate(self, vdi):
        meta = read_metadata(self.path, vdi)
        if self.writable[vdi]:
            meta["content_id"] = ""
            write_metadata(self.path, vdi, meta)
        data = meta["data"]
        if data not in self.tapdisks:
            raise Backend_error("VDI_NOT_ATTACHED", [ vdi ])
        tapdisk = self.tapdisks[data]
        tapdisk.close()
        tapdisk.open(data_type(self.path, data), data_path(self.path, data))

    def deactivate(self, vdi):
        meta = read_metadata(self.path, vdi)
        if meta["content_id"] == "":
            meta["content_id"] = util.gen_uuid()
            write_metadata(self.path, vdi, meta)
        data = meta["data"]
        if data not in self.tapdisks:
            raise Backend_error("VDI_NOT_ATTACHED", [ vdi ])
        self.tapdisks[data].close()

        self.open_dummy_vhd(meta, self.tapdisks[data])

    def detach(self, vdi):
        del self.writable[vdi]
        md = read_metadata(self.path, vdi)
        data = md["data"]
        if data not in self.tapdisks:
            raise Backend_error("VDI_NOT_ATTACHED", [ vdi ])
        self.tapdisks[data].close()
        self.tapdisks[data].detach()
        self.tapdisks[data].free()
        del self.tapdisks[data]

    def compose(self, vdi1, vdi2):
        # This operates on the vhds, not the VDIs
        leaf = read_metadata(vdi2)["data"]
        parent = read_metadata(vdi1)["data"]

        # leaf must be already a leaf of some other parent
        if "parent" not in read_data(self.path, leaf):
            raise Backend_error("VHD_NOT_LEAF", [ vdi2 ])

        leaf_path = self.path + "/" + data_dir + "/" + leaf + vhd_suffix
        parent_path = self.path + "/" + data_dir + "/" + parent + vhd_suffix
        vhd.reparent(leaf_path, parent_path)

        # cause tapdisk to reopen the vhd chain
        if leaf in self.tapdisks:
            self.tapdisks[leaf].reopen()
        else:
            log("VDI %s (%s.vhd) has no active tapdisk -- nothing to reopen" % (vdi2, leaf))


# A map from attached SR reference -> Repo instance
repos = {}

# A map from attached SR reference -> device_config parameters
sr_device_config = {}

# Location where we'll mount temporary filesystems
var_run = "/var/run/nonpersistent/fs"

class Query(Query_skeleton):
    def __init__(self):
        Query_skeleton.__init__(self)
    def query(self, dbg):
        return { "driver": "fs",
                 "name": "filesystem SR",
                 "description": "VDIs are stored as files in an existing filesystem",
                 "vendor": "XCP",
                 "copyright": "see the source code",
                 "version": "2.0",
                 "required_api_version": "2.0",
                 "features": [
                feature_vdi_create,
                feature_vdi_delete,
                feature_vdi_attach,
                feature_vdi_detach,
                feature_vdi_activate,
                feature_vdi_deactivate,
                feature_vdi_clone,
                feature_vdi_snapshot,
                feature_vdi_reset_on_boot
                ],
                 "configuration": { "path": "local filesystem path where the VDIs are stored",
                                    "server": "remote server exporting VDIs",
                                    "serverpath": "path on the remote server" }
                 }
    def diagnostics(self, dbg):
        lines = []
        for sr in repos.keys():
            r = repos[sr]
            vdis = {} # vdi to idx
            ds = {} # data to idx
            # Represent each VDI as a record
            lines = lines + [
                "digraph \"%s\" {" % sr,
                "node [shape=record];"
                ]
            idx = 0
            metadata = read_all_metadata(r.path)
            for vdi in metadata.keys():
                vdis[vdi] = idx
                lines.append("%s [label=\"%s:%s\"];" % (str(idx), metadata[vdi]["name_label"], str(vdi)))
                idx = idx + 1
            lines.append("node [shape=circle];")
            tree = read_tree(r.path)
            for d in tree.keys():
                ds[d] = idx
                lines.append("%s [label=\"%s\"];" % (str(idx), str(d)))
                idx = idx + 1
            for vdi in metadata.keys():
                lines.append("%s -> %s;" % (vdis[vdi], ds[metadata[vdi]["data"]]))
            for d in tree.keys():
                data = tree[d]
                if "parent" in data:
                    lines.append("%s -> %s;" % (ds[d], ds[data["parent"]]))
            lines = lines + [
                "}"
                ]
        return "\n".join(lines)


class SR(SR_skeleton):
    def __init__(self):
        SR_skeleton.__init__(self)

    def list(self, dbg):
        return repos.keys()
    def create(self, dbg, sr, device_config, physical_size):
        if sr in repos:
            raise (Sr_attached(sr))
        if "path" in device_config:
            path = device_config["path"]
            if not(os.path.exists(path)):
                raise Backend_error("SR directory doesn't exist", [ path ])
        elif "server" in device_config and "serverpath" in device_config:
            remote = "%s:%s" % (device_config["server"], device_config["serverpath"])
            # XXX check remote service exists
    def attach(self, dbg, sr, device_config):
        path = None
        if "path" in device_config:
            path = device_config["path"]
            if not(os.path.exists(path)):
                raise Backend_error("SR directory doesn't exist", [ path ])
        elif "server" in device_config and "serverpath" in device_config:
            remote = "%s:%s" % (device_config["server"], device_config["serverpath"])
            for m in mount.list(var_run):
                if m.remote == remote:
                    path = m.local
                    break
            if not path:
                m = mount.Mount(remote, var_run + "/" + sr)
                m.mount()
                path = m.local
        else:
            raise Backend_error("#needabettererror", [ "bad device config" ])
        name = "unknown"
        if "myname" in device_config:
            name = device_config["myname"]
        write_repo_state(sr, { "name": name, "path": path })
        repos[sr] = Repo(name, path)
        sr_device_config[sr] = device_config

    def detach(self, dbg, sr):
        if not sr in repos:
            log("SR isn't attached, returning success")
        else:
            device_config = sr_device_config[sr]
            if "path" in device_config:
                pass
            elif "server" in device_config and "serverpath" in device_config:
                remote = "%s:%s" % (device_config["server"], device_config["serverpath"])
                for m in mount.list(var_run):
                    if m.remote == remote:
                        m.umount()
            else:
                assert False # see attach above
            del repos[sr]
            delete_repo_state(sr)
            del sr_device_config[sr]
    def destroy(self, dbg, sr):
        pass
    def reset(self, dbg, sr):
        """Operations which act on Storage Repositories"""
        raise Unimplemented("SR.reset")
    def scan(self, dbg, sr):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].scan()

class VDI(VDI_skeleton):
    def __init__(self):
        VDI_skeleton.__init__(self)

    def create(self, dbg, sr, vdi_info):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].create(vdi_info)

    def clone(self, dbg, sr, vdi_info):
        """Create a writable clone of a VDI"""
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].clone(vdi_info["vdi"], vdi_info)
    def snapshot(self, dbg, sr, vdi_info):
        """Create a read/only snapshot of a VDI"""
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].snapshot(vdi_info["vdi"], vdi_info)
    def destroy(self, dbg, sr, vdi):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].destroy(vdi)
    def stat(self, dbg, sr, vdi):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].stat(vdi)
    def set_persistent(self, dbg, sr, vdi, persistent):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].set_persistent(vdi, persistent)
    def set_content_id(self, dbg, sr, vdi, content_id):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].set_content_id(vdi, content_id)
    def get_by_name(self, dbg, sr, name):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].get_by_name(name)
    def similar_content(self, dbg, sr, vdi):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].similar_content(vdi)
    def epoch_begin(self, dbg, sr, vdi):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].epoch_begin(vdi)
    def epoch_end(self, dbg, sr, vdi):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].epoch_end(vdi)
    def attach(self, dbg, dp, sr, vdi, read_write):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].attach(vdi, read_write)
    def activate(self, dbg, dp, sr, vdi):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].activate(vdi)
    def deactivate(self, dbg, dp, sr, vdi):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].deactivate(vdi)
    def detach(self, dbg, dp, sr, vdi):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].detach(vdi)
    def compose(self, dbg, sr, vdi1, vdi2):
        if not sr in repos:
            raise Sr_not_attached(sr)
        return repos[sr].compose(vdi1, vdi2)

whitelist = [
    "jQuery-Visualize/js/excanvas.js",
    "jQuery-Visualize/js/visualize.jQuery.js",
    "jQuery-Visualize/css/visualize.css",
    "jQuery-Visualize/css/visualize-light.css",
    "mobile.html",
    "index.html",
    "monkey.model",
    ]
rewrites = {
    "": "mobile.html"
}
wwwroot = None
class RequestHandler(xcp.RequestHandler):
    def do_GET(self):
        log("foo %s %s" % (repr(self), self.path))
        response = None
        path = self.path
        path = path.strip("/")
        if path in rewrites:
            path = rewrites[path]
        if path not in whitelist:
            log("%s not in whitelist: 404" % path)
            self.send_response(404)
            self.end_headers()

            # shut down the connection
            self.wfile.flush()
            self.connection.shutdown(1)
        else:
            if wwwroot:
                path = os.path.join(wwwroot, path)
            size = os.stat(path).st_size
            f = open(path, "r")
            try:
                self.send_response(200)
                if self.path.endswith(".html"):
                    self.send_header("Content-type", "text/html")
                elif self.path.endswith(".css"):
                    self.send_header("Content-type", "text/css")
                if self.path.endswith(".js"):
                    self.send_header("Content-type", "application/x-javascript")
                self.send_header("Content-length", str(size))
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(f.read())
                # shut down the connection
                self.wfile.flush()
                self.connection.shutdown(1)
            finally:
                f.close()

if __name__ == "__main__":
    from optparse import OptionParser
    import ConfigParser

    settings = {
        "log": "stdout:",
        "port": None,
        "interface": None,
        "ip": None,
        "socket": "/var/xapi/sm/fs",
        "daemon": False,
        "config": "/etc/xcp-sm-fs.conf",
        "pidfile": "./xcp-sm-fs.pid",
        "www": "../js/",
        }
    string_t = lambda x:x
    int_t = lambda x:int(x)
    bool_t = lambda x:x == "True"
    types = {
        "log": string_t,
        "port": int_t,
        "interface": string_t,
        "ip": string_t,
        "socket": string_t,
        "daemon": bool_t,
        "config": string_t,
        "pidfile": string_t,
        "www": string_t,
    }

    log("settings = %s" % repr(settings))
    
    parser = OptionParser()
    parser.add_option("-l", "--log", dest="logfile", help="log to LOG", metavar="LOG")
    parser.add_option("-p", "--port", dest="port", help="listen on PORT", metavar="PORT")
    parser.add_option("-e", "--interface", dest="interface", help="listen on network interface", metavar="ethN")
    parser.add_option("-i", "--ip-addr", dest="ip", help="listen on IP", metavar="IP")
    parser.add_option("-s", "--socket", dest="socket", help="listen on Unix domain socket", metavar="SOCK")
    parser.add_option("-d", "--daemon", action="store_true", dest="daemon", help="run as a background daemon", metavar="DAEMON")
    parser.add_option("-c", "--config", dest="config", help="read options from a config file", metavar="CONFIG")
    (options, args) = parser.parse_args()
    options = options.__dict__

    # Read base options from the config file, allow command-line to override
    if "config" in options and options["config"]:
        settings["config"]= options["config"]

    if os.path.exists(settings["config"]):
        log("Reading config file: %s" % (settings["config"]))
        config_parser = ConfigParser.ConfigParser()
        config_parser.read(settings["config"])
        for (setting, value) in config_parser.items("global"):
            if setting in settings:
                settings[setting] = types[setting](value)
                log("config settings[%s] <- %s" % (setting, repr(settings[setting])))

    for setting in settings:
        if setting in options and options[setting]:
            settings[setting] = types[setting](options[setting])
            log("option settings[%s] <- %s" % (setting, repr(settings[setting])))
            
    if settings["log"] == "syslog:":
        xcp.use_syslog = True
        xcp.reopenlog(None)
    elif settings["log"] == "stdout:":
        xcp.use_syslog = False
        xcp.reopenlog("stdout:")
    else:
        xcp.use_syslog = False
        xcp.reopenlog(settings["log"])

    tcp = (settings["ip"] or settings["interface"]) and settings["port"]
    unix = settings["socket"]
    if not tcp and not unix:
        print >>sys.stderr, "Need an --ip-addr/--interface and --port or a --socket. Use -h for help"
        sys.exit(1)

    if settings["interface"]:
        settings["ip"] = util.address_from_interface(settings["interface"])
        log("using ip address %s of interface %s" % (settings["ip"], settings["interface"]))

    if settings["daemon"]:
        log("daemonising")
        xcp.daemonize()
    log("writing pid (%d) to %s" % (os.getpid(), settings["pidfile"]))
    pidfile = open(settings["pidfile"], "w")
    try:
        pidfile.write(str(os.getpid()))
    finally:
        pidfile.close()

    if not (os.path.exists(repo_state_dir)):
        os.mkdir(repo_state_dir)

    for sr in list_repo_state():
        log("loading repo state for: %s" % sr)
        info = read_repo_state(sr)
        repos[sr] = Repo(info["name"], info["path"])

    wwwroot = settings["www"]

    server = None
    if tcp:
        log("will listen on %s:%d" % (settings["ip"], int(settings["port"])))
        server = xcp.TCPServer(settings["ip"], int(settings["port"]), requestHandler=RequestHandler)
    else:
        log("will listen on %s" % settings["socket"])
        server = xcp.UnixServer(settings["socket"], requestHandler=RequestHandler)

    server.register_introspection_functions() # for debugging
    server.register_instance(storage_server_dispatcher(Query = Query_server_dispatcher(Query()), VDI = VDI_server_dispatcher(VDI()), SR = SR_server_dispatcher(SR())))
    log("serving requests forever")
    server.serve_forever()
