# `dhall-kubernetes`

<img src="logo/dhall-kubernetes-logo.svg" alt="dhall-kubernetes logo" height="300px"/>

`dhall-kubernetes` contains [Dhall][dhall-lang] bindings to [Kubernetes][kubernetes],
so you can generate Kubernetes objects definitions from Dhall expressions.
This will let you easily typecheck, template and modularize your Kubernetes definitions.

## Why do I need this

Once you build a slightly non-trivial Kubernetes setup, with many objects floating
around, you'll encounter several issues:
1. Writing the definitions in YAML is really verbose, and the actually important
  things don't stand out that much
2. Ok I have a bunch of objects that'll need to be configured together, how do I share data?
3. I'd like to reuse an object for different environments, but I cannot make it parametric..
4. In general, I'd really love to reuse parts of some definitions in other definitions
5. Oh no, I typoed a key and I had to wait until I pushed to the cluster to get an error back :(

The natural tendency is to reach for a templating language + a programming language to orchestrate that + some more configuration for it...
But this is just really messy (been there), and we can do better.

Dhall solves all of this, being a programming language with builtin templating,
all while being non-Turing complete, strongly typed and [strongly normalizing][normalization]
(i.e.: reduces everything to a normal form, no matter how much abstraction you build),
so saving you from the *"oh-noes-I-made-my-config-in-code-and-now-its-too-abstract"* nightmare.

For a Dhall Tutorial, see [the website][dhall-website], or the [readme of the project][dhall-lang],
or the [full tutorial][dhall-tutorial].

## Prerequisites

**NOTE**: `dhall-kubernetes` requires at least version `1.27.0` of [the interpreter](https://github.com/dhall-lang/dhall-haskell)
(version `11.0.0` of the language).

## Quickstart - a simple Deployment

Let's say we'd like to configure a Deployment exposing an `nginx` webserver.

In the following example, we:
1. Import the Kubernetes definitions as a Dhall package (the `package.dhall` file) from the local repo.
   In your case you will want to replace the local path with a remote one, e.g.
   `https://raw.githubusercontent.com/dhall-lang/dhall-kubernetes/master/package.dhall`
   Note: the `sha256:..` is applied to some imports so that:
     1. the import is cached locally after the first evaluation, with great time savings (and avoiding network calls)
     2. prevent execution if the content of the file changes. This is a security feature, and you
        can read more [in Dhall's "Security Guarantees" document][security-hashes]
   Note: instead of using the `package.dhall` from the `master` branch, you may want to use a tagged release,
     as the contents of the `master` branch are liable to change without warning.
2. Define the [Deployment][deployment] using the schema pattern and hardcoding the deployment details:

```dhall
-- examples/deploymentSimple.dhall

let kubernetes =
      ../package.dhall sha256:3ea8628b704704de295261dfc7626c15247c589c10a266f970cade262543fdda

let deployment =
      kubernetes.Deployment::{
      , metadata = kubernetes.ObjectMeta::{ name = "nginx" }
      , spec =
          Some
            kubernetes.DeploymentSpec::{
            , replicas = Some 2
            , template =
                kubernetes.PodTemplateSpec::{
                , metadata = kubernetes.ObjectMeta::{ name = "nginx" }
                , spec =
                    Some
                      kubernetes.PodSpec::{
                      , containers =
                          [ kubernetes.Container::{
                            , name = "nginx"
                            , image = Some "nginx:1.15.3"
                            , ports =
                                [ kubernetes.ContainerPort::{
                                  , containerPort = 80
                                  }
                                ]
                            }
                          ]
                      }
                }
            }
      }

in  deployment

```

We then run this through `dhall-to-yaml` to generate our Kubernetes definition:

```bash
dhall-to-yaml --omitEmpty < examples/deploymentSimple.dhall
```

And we get:
```yaml
## examples/out/deploymentSimple.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 2
  template:
    metadata:
      name: nginx
    spec:
      containers:
        - image: nginx:1.15.3
          name: nginx
          ports:
            - containerPort: 80

```

## More modular: defining an Ingress

The above is cool, but hardcoding data is not that cool.

So in a more realistic deployment you'll probably want to define:
- some `MyService` type that contains the config settings relevant to your deployments
- some functions parametrized by this type, so that you can produce objects to send to k8s
  by just applying these functions to `MyService` objects

This is useful because then you can define your `Service`s separately from the Kubernetes logic,
and reuse those objects for configuring other things (e.g. configuring the services themselves,
templating documentation, configuring Terraform deployments, you name it).

As an example of that, next we'll define an Ingress (an [Nginx Ingress][nginx-ingress] in this case),
containing stuff like TLS certs and routes for every service - see the [schema][Ingress].

Things to note in the following example:
- we define the `Service` type inline in the file, but in your case you'll want to have a
  separate `./Service.dhall` file (so you can share around the project)
- we define functions to create the TLS definitions and the routes, so that we can `map`
  them over the list of services.
- we also defined the list of `services` inline, but you should instead return the
  `mkIngress` function instead of applying it, so you can do something like
  `dhall-to-yaml --omitEmpty <<< "./mkIngress.dhall ./myServices.dhall"`

```dhall
-- examples/ingress.dhall

let Prelude = ../Prelude.dhall

let map = Prelude.List.map

let kv = Prelude.JSON.keyText

let kubernetes =
      ../package.dhall sha256:3ea8628b704704de295261dfc7626c15247c589c10a266f970cade262543fdda

let Service = { name : Text, host : Text, version : Text }

let services = [ { name = "foo", host = "foo.example.com", version = "2.3" } ]

let makeTLS
    : Service → kubernetes.IngressTLS.Type
    =   λ(service : Service)
      → { hosts = [ service.host ]
        , secretName = Some "${service.name}-certificate"
        }

let makeRule
    : Service → kubernetes.IngressRule.Type
    =   λ(service : Service)
      → { host = Some service.host
        , http =
            Some
              { paths =
                  [ { backend =
                        { serviceName = service.name
                        , servicePort = kubernetes.IntOrString.Int 80
                        }
                    , path = None Text
                    }
                  ]
              }
        }

let mkIngress
    : List Service → kubernetes.Ingress.Type
    =   λ(inputServices : List Service)
      → let annotations =
              [ kv "kubernetes.io/ingress.class" "nginx"
              , kv "kubernetes.io/ingress.allow-http" "false"
              ]

        let defaultService =
              { name = "default"
              , host = "default.example.com"
              , version = " 1.0"
              }

        let ingressServices = inputServices # [ defaultService ]

        let spec =
              kubernetes.IngressSpec::{
              , tls =
                  map Service kubernetes.IngressTLS.Type makeTLS ingressServices
              , rules =
                  map
                    Service
                    kubernetes.IngressRule.Type
                    makeRule
                    ingressServices
              }

        in  kubernetes.Ingress::{
            , metadata =
                kubernetes.ObjectMeta::{
                , name = "nginx"
                , annotations = annotations
                }
            , spec = Some spec
            }

in  mkIngress services

```

As before we get the yaml out by running:

```bash
dhall-to-yaml --omitEmpty < examples/ingress.dhall
```

Result:
```yaml
## examples/out/ingress.yaml

apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.allow-http: "false"
    kubernetes.io/ingress.class: nginx
  name: nginx
spec:
  rules:
    - host: foo.example.com
      http:
        paths:
          - backend:
              serviceName: foo
              servicePort: 80
    - host: default.example.com
      http:
        paths:
          - backend:
              serviceName: default
              servicePort: 80
  tls:
    - hosts:
        - foo.example.com
      secretName: foo-certificate
    - hosts:
        - default.example.com
      secretName: default-certificate

```

## FAQ

#### Can I generate a YAML file with many objects in it?

It is usual for k8s YAML files to include multiple objects separated by `---` ("documents" in YAML lingo),
so you might want to do it too.

If the objects have the same type, this is very easy: you return a Dhall list containing the
objects, and use the `--documents` flag, e.g.:

```bash
dhall-to-yaml --documents --omitEmpty <<< "let a = ./examples/deploymentSimple.dhall in [a, a]"
```

If the objects are of different type, it's not possible to have separate documents in the same YAML file.
However, since [k8s has a builtin `List` type for these cases](https://github.com/kubernetes/kubernetes/blob/master/hack/testdata/list.yaml),
it's possible to use it together with the [union type of all k8s types that we generate][typesUnion].

So if we want to deploy e.g. a Deployment and a Service together, we can do:

```dhall
let k8s = ./typesUnion.dhall

in
{ apiVersion = "v1"
, kind = "List"
, items =
  [ k8s.Deployment ./my-deployment.dhall
  , k8s.Service ./my-service.dhall
  ]
}
```


## Projects Using `dhall-kubernetes`

* [dhall-prometheus-operator][dhall-prometheus-operator]: Provides types and default records for [Prometheus Operators][prometheus-operator].


## Development

### Updating the nixpkgs snapshot (and kubernetes version)

Run
```bash
./scripts/update-nixpkgs.sh
./scripts/generate.sh
```
If the tests fail, rollback. If they don't then you have sucessfully upgraded!

### Tests

All tests are defined in `release.nix`. We run these tests in CI in a [Hydra
project][hydra-project].

You can run the tests locally with the following command:

```bash
nix build --file ./release.nix
```

### Generating `types` `default` and `README.md`

Running `scripts/generate.sh` will generate all dhall files from the kubernetes
swagger specification, and copy them to `types` and `default`. It will also
generate `README.md` from `docs/README.md.dhall`.

If you make changes to `scripts/convert.py` or `docs/README.md.dhall`, you need
to run this command afterwards.


[stack]: https://haskellstack.org/
[hydra-project]: http://hydra.dhall-lang.org/project/dhall-kubernetes
[dhall-lang]: https://github.com/dhall-lang/dhall-lang
[dhall-website]: https://dhall-lang.org/
[security-hashes]: https://github.com/dhall-lang/dhall-lang/wiki/Safety-guarantees#code-injection
[typesUnion]: https://github.com/dhall-lang/dhall-kubernetes/blob/master/typesUnion.dhall
[kubernetes]: https://kubernetes.io/
[normalization]: https://en.wikipedia.org/wiki/Normalization_property_(abstract_rewriting)
[nginx-ingress]: https://github.com/kubernetes/ingress-nginx
[dhall-tutorial]: http://hackage.haskell.org/package/dhall-1.28.0/docs/Dhall-Tutorial.html
[deployment]: ./schemas/io.k8s.api.apps.v1.Deployment.dhall
[Ingress]: ./schemas/io.k8s.api.extensions.v1beta1.Ingress.dhall
[prometheus-operator]: https://github.com/coreos/prometheus-operator
[dhall-prometheus-operator]: https://github.com/coralogix/dhall-prometheus-operator
