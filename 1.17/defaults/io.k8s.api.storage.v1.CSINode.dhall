{ apiVersion = "storage.k8s.io/v1"
, kind = "CSINode"
, metadata = ./io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta.dhall
, spec = ./io.k8s.api.storage.v1.CSINodeSpec.dhall
}
