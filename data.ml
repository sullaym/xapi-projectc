open Types

let domain = {
  Arg.name = "domain";
  ty = Type.Name "domain";
  description = "An opaque string which represents the Xen domain.";
}

let uri = {
  Arg.name = "uri";
  ty = Type.Name "uri";
  description = "A URI which represents how to access the volume disk data.";
}

let backend = {
  Arg.name = "backend";
  ty = Type.Name "backend";
  description = "The Xen block backend configuration."
}

let implementation = Type.Variant (
  ("blkback", Type.(Basic String), "use kernel blkback with the given 'params' key"), [
   "tapdisk3", Type.(Basic String), "use userspace tapdisk3 with the given 'params' key";
   "qdisk", Type.(Basic String), "use userspace qemu qdisk with the given 'params' key"
  ])

let backend_decl = Type.Struct (
  ("domain_uuid", Type.(Basic String), "UUID of the domain hosting the backend"), [
  "implementation", implementation, "choice of implementation technology";
  ])

let api =
  {
    Interfaces.name = "Datapath plugin";
    title = "The Datapath plugin interface";
    description = String.concat " " [
      "The Datapath plugin takes a URI which points to virtual disk data and";
      "chooses a Xen datapath implementation: driver domain, blkback implementation";
      "and caching strategy."
    ];
    exn_decls = [
    ];
    type_decls = [
      {
        TyDecl.name = "domain";
        description = String.concat " " [
          "A string representing a Xen domain on the local host.";
          "The string is guaranteed to be unique per-domain but it is not";
          "guaranteed to take any particular form. It may (for example)";
          "be a Xen domain id, a Xen VM uuid or a Xenstore path or anything";
          "else chosen by the toolstack. Implementations should not assume";
          "the string has any meaning.";
        ];
        ty = Type.(Basic String);
      }; {
        TyDecl.name = "uri";
        description = String.concat " " [
          "A URI representing the means for accessing the volume data.";
          "The interpretation of the URI is specific to the implementation.";
          "Xapi will choose which implementation to use based on the URI";
          "scheme.";
        ];
        ty = Type.(Basic String);
      }; {
        TyDecl.name = "backend";
        description = String.concat " " [
          "A description of which Xen block backend to use. The toolstack";
          "needs this to setup the shared memory connection to blkfront";
          "in the VM.";
        ];
        ty = backend_decl;
      }
    ];
    interfaces = [
      {
        Interface.name = "Datapath";
        description = String.concat " " [
          "Xapi will call the functions here on VM start/shutdown/suspend/resume/migrate.";
          "Every function is idempotent. Every function takes a domain parameter";
          "which allows the implementation to track how many domains are currently";
          "using the volume.";
        ];
        type_decls = [
         ];
        methods = [
          {
            Method.name = "attach";
            description = String.concat " "[
              "[attach uri domain] prepares a connection between the storage";
              "named by [uri] and the Xen domain with id [domain]. The return";
              "value is the information needed by the Xen toolstack to setup";
              "the shared-memory blkfront protocol. Note that the same volume";
              "may be simultaneously attached to multiple hosts";
              "for example over a migrate. If an implementation needs to perform";
              "an explicit handover, then it should implement [activate] and";
              "[deactivate]. This function is idempotent.";
            ];
            inputs = [
              uri;
              domain;
            ];
            outputs = [
              backend;
            ];
          }; {
            Method.name = "activate";
            description = String.concat " " [
              "[activate uri domain] is called just before a VM needs to";
              "read or write its disk. This is an opportunity for an implementation";
              "which needs to perform an explicit volume handover to do it.";
              "This function is called in the migration downtime window so";
              "delays here will be noticeable to users and should be minimised.";
              "This function is idempotent.";
            ];
            inputs = [
              uri;
              domain;
            ];
            outputs = [
            ];
          }; {
            Method.name = "deactivate";
            description = String.concat " " [
              "[deactivate uri domain] is called as soon as a VM has finished";
              "reading or writing its disk. This is an opportunity for an";
              "implementation which needs to perform an explicit volume handover";
              "to do it. This function is called in the migration downtime window";
              "so delays here will be noticeable to users and should be minimised.";
              "This function is idempotent.";
            ];
            inputs = [
              uri;
              domain;
            ];
            outputs = [
            ];
          }; {
            Method.name = "detach";
            description = String.concat " " [
              "[detach uri domain] is called sometime after a VM has finished";
              "reading or writing its disk. This is an opportunity to clean up";
              "any resources associated with the disk. This function is called";
              "outside the migration downtime window so can be slow without";
              "affecting users. This function is idempotent.";
              "This function should never fail. If an implementation is unable";
              "to perform some cleanup right away then it should queue the";
              "action internally. Any error result represents a bug in the";
              "implementation.";
            ];
            inputs = [
              uri;
              domain;
            ];
            outputs = [
            ];
          }
        ]
      }
    ];
  }
