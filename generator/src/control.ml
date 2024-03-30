open Types
open Type

let api =
  let volume_decl =
    Type.(Struct(
        ( "key", Name "key", String.concat " " [
          "A primary key for this volume. The key must be unique";
          "within the enclosing Storage Repository (SR). A typical value would";
          "be a filename or an LVM volume name."
          ]),
        [ "name", Basic String, String.concat " " [
          "Short, human-readable label for the volume. Names are commonly used by";
          "when displaying short lists of volumes.";
          ];
          "description", Basic String, String.concat " " [
            "Longer, human-readable description of the volume. Descriptions are";
            "generally only displayed by clients when the user is examining";
            "volumes individually.";
          ];
          "read_write", Basic Boolean, String.concat " " [
            "True means the VDI may be written to, false means the volume is";
            "read-only. Some storage media is read-only so all volumes are";
            "read-only; for example .iso disk images on an NFS share. Some";
            "volume are created read-only; for example because they are snapshots";
            "of some other VDI.";
          ];
          "virtual_size", Basic Int64, String.concat " " [
            "Size of the volume from the perspective of a VM (in bytes)";
          ];
          "uri", Array (Basic String), String.concat " " [
            "A list of URIs which can be opened and used for I/O. A URI could ";
            "reference a local block device, a remote NFS share, iSCSI LUN or ";
            "RBD volume. In cases where the data may be accessed over several ";
            "protocols, he list should be sorted into descending order of ";
            "desirability. Xapi will open the most desirable URI for which it has ";
            "an available datapath plugin.";
          ]
        ]
      )) in
  let volume = Type.Name "volume" in
  let sr = {
    Arg.name = "sr";
    ty = Type.(Basic String);
    description = "The Storage Repository";
  } in
  let key = {
    Arg.name = "key";
    ty = Type.(Basic String);
    description = "The volume key";
  } in
  let uri = {
    Arg.name = "uri";
    ty = Type.(Basic String);
    description = "The Storage Repository URI";
  } in
  {
    Interfaces.name = "v";
    title = "The Volume plugin interface";
    description =
      String.concat " " [
        "The xapi toolstack delegates all storage control-plane functions to ";
        "\"Volume plugins\".These plugins";
        "allow the toolstack to create/destroy/snapshot/clone volumes which";
        "are organised into groups called Storage Repositories (SR). Volumes";
        "have a set of URIs which can be used by the \"Datapath plugins\"";
        "to connect the disk data to VMs.";
      ];
    exn_decls = [
      {
        TyDecl.name = "Sr_not_attached";
        description = "An SR must be attached in order to access volumes";
        ty = Type.(Basic String)
      }; {
        TyDecl.name = "SR_does_not_exist";
        description = "The specified SR could not be found";
        ty = Type.(Basic String)
      }; {
        TyDecl.name = "Volume_does_not_exist";
        description = "The specified volume could not be found in the SR";
        ty = Type.(Basic String)
      }; {
        TyDecl.name = "Unimplemented";
        description = "The operation has not been implemented";
        ty = Type.(Basic String);
      }; {
        TyDecl.name = "Cancelled";
        description = "The task has been asynchronously cancelled";
        ty = Type.(Basic String);
      };
    ];
    type_decls = [
      {
        TyDecl.name = "key";
        description = String.concat " " [
          "Primary key for a volume. This can be any string which";
          "is meaningful to the implementation. For example this could be an";
          "NFS filename, an LVM LV name or even a URI. This string is";
          "abstract."
          ];
        ty = Type.(Basic String);
      }; {
        TyDecl.name = "sr";
        description = String.concat " " [
          "Primary key for a specific Storage Repository. This can be any ";
          "string which is meaningful to the implementation. For example this ";
          "could be an NFS directory name, an LVM VG name or even a URI.";
          "This string is abstract.";
        ];
        ty = Type.(Basic String);
      }; {
        TyDecl.name = "volume";
        description = String.concat " " [
          "A set of properties associated with a volume. These properties can ";
          "change dynamically and can be queried by the Volume.stat call.";
        ];
        ty = volume_decl
      }

    ];
    interfaces =
      [
        {
          Interface.name = "Volume";
          description = "Operations which operate on volumes (also known as Virtual Disk Images)";
          type_decls = [];
          methods = [
            {
              Method.name = "create";
              description = String.concat " " [
                "[create sr name description size] creates a new volume in [sr]";
                "with [name] and [description]. The volume will have size";
                ">= [size] i.e. it is always permissable for an implementation";
                "to round-up the volume to the nearest convenient block size";
              ];
              inputs = [
                sr;
                {
                  Arg.name = "name";
                  ty = Basic String;
                  description = String.concat " " [
                    "A human-readable name to associate with the new disk. This";
                    "name is intended to be short, to be a good summary of the";
                    "disk."
                  ]
                };
                {
                  Arg.name = "description";
                  ty = Basic String;
                  description = String.concat " " [
                    "A human-readable description to associate with the new";
                    "disk. This can be arbitrarily long, up to the general";
                    "string size limit."
                  ]
                };
                {
                  Arg.name = "size";
                  ty = Basic Int64;
                  description = String.concat " " [
                    "A minimum size (in bytes) for the disk. Depending on the";
                    "characteristics of the implementation this may be rounded";
                    "up to (for example) the nearest convenient block size. The";
                    "created disk will not be smaller than this size.";
                  ]
                };
              ];
              outputs = [
                { Arg.name = "volume";
                  ty = volume;
                  description = "Properties of the created volume";
                }
              ];
            }; {
              Method.name = "snapshot";
              description = String.concat " " [
                "[snapshot sr volume] creates a new volue which is a ";
                "snapshot of [volume] in [sr]. Snapshots should never be";
                "written to; they are intended for backup/restore only.";
              ];
              inputs = [
                sr;
                key;
              ];
              outputs = [
                { Arg.name = "volume";
                  ty = volume;
                  description = "Properties of the created volume";
                }
              ];
            }; {
              Method.name = "clone";
              description = String.concat " " [
                "[clone sr volume] creates a new volume which is a writable";
                "clone of [volume] in [sr].";
              ];
              inputs = [
                sr;
                key;
              ];
              outputs = [
                { Arg.name = "volume";
                  ty = volume;
                  description = "Properties of the created volume";
                }
              ];
            }; {
              Method.name = "destroy";
              description = "[destroy sr volume] removes [volume] from [sr]";
              inputs = [
                sr;
                key;
              ];
              outputs = [
              ];
            }; {
              Method.name = "resize";
              description = String.concat " " [
                "[resize sr volume new_size] enlarges [volume] to be at least";
                "[new_size].";
              ];
              inputs = [
                sr;
                key;
                { Arg.name = "new_size";
                  ty = Basic Int64;
                  description = "New disk size"
                }
            ];
              outputs = [
              ];
            }; {
              Method.name = "stat";
              description = String.concat " " [
                "[stat sr volume] returns metadata associated with [volume].";
              ];
              inputs = [
                sr;
                key;
              ];
              outputs = [
                { Arg.name = "volume";
                  ty = volume;
                  description = "Volume metadata";
                }
              ];
            };
          ]
        }; {
          Interface.name = "SR";
          description = "Operations which act on Storage Repositories";
          type_decls = [];
          methods = [
            {
              Method.name = "create";
              description = "[create uri configuration]: creates a fresh SR";
              inputs = [
                uri;
                { Arg.name = "configuration";
                  ty = Type.(Dict(String, Basic String));
                  description = String.concat " " [
                    "Plugin-specific configuration which describes where and";
                    "how to create the storage repository. This may include";
                    "the physical block device name, a remote NFS server and";
                    "path or an RBD storage pool.";
                  ];
                };
              ];
              outputs = []
            };
            {
              Method.name = "attach";
              description = String.concat " "[
                "[attach uri]: attaches the SR to the local host. Once an SR";
                "is attached then volumes may be manipulated.";
              ];
              inputs = [
                uri;
              ];
              outputs = [
                sr;
              ];
            }; {
              Method.name = "detach";
              description = String.concat " " [
                "[detach sr]: detaches the SR, clearing up any associated";
                "resources. Once the SR is detached then volumes may not be";
                "manipulated.";
              ];
              inputs = [
                sr;
              ];
              outputs = [
              ];
            }; {
              Method.name = "destroy";
              description = String.concat " "[
                "[destroy sr]: destroys the [sr] and deletes any volumes";
                "associated with it. Note that an SR must be attached to be";
                "destroyed; otherwise Sr_not_attached is thrown.";
              ];
              inputs = [
                sr;
              ];
              outputs = [
              ];
            };
             {
              Method.name = "ls";
              description = String.concat " " [
                "[ls sr] returns a list of volumes";
                "contained within an attached SR.";
              ];
              inputs = [
                sr;
              ];
              outputs = [
                {
                  Arg.name = "volumes";
                  ty = Type.(Array (Name "volume"));
                  description = "List of all the visible volumes in the SR";
                }
              ];
            }
          ]
        }
      ]
  }
