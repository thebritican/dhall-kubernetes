{ apiVersion = "admissionregistration.k8s.io/v1"
, kind = "ValidatingWebhookConfiguration"
, metadata = ./io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta.dhall
, webhooks =
    [] : List
           ./../types/io.k8s.api.admissionregistration.v1.ValidatingWebhook.dhall
}
