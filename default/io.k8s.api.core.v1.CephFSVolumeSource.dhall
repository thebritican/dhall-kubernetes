\(_params : {monitors : (List Text)}) ->
{ monitors = _params.monitors
, path = ([] : Optional (Text))
, readOnly = ([] : Optional (Bool))
, secretFile = ([] : Optional (Text))
, secretRef = ([] : Optional (../types/io.k8s.api.core.v1.LocalObjectReference.dhall))
, user = ([] : Optional (Text))
} : ../types/io.k8s.api.core.v1.CephFSVolumeSource.dhall
