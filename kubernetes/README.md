# auroral-node-helm-chart

Helm chart for auroral node <https://github.com/AuroralH2020/auroral-node> created with [`kompose`](https://kompose.io/user-guide/).

The manifests for the gateway is valid only for new auroral js gateway

## Getting started

1. install [`helm`](https://helm.sh/docs/intro/install/)
1. have a kubernetes cluster available and a `kubeconfig` set up
1. clone the repository with `git clone https://github.com/Aiguasol/auroral-node-helm-chart`
1. `cd auroral-node-helm-chart`
1. `cp ./manifests/values.yaml ./manifests/myvalues.yaml`
1. Update the values for the variables in `myvalues.yaml` with your own deployment values.
1. Evaluate and debug the resulting chart, or install it right away

   1. Debugging (passing `--dry-run` and `--debug`)

      ```shell
      helm --kubeconfig ~/.kube/configs/yourkubeconfig -n auroral-node install auroral-node-chart ./manifests --debug --dry-run
      ```

   1. Installing

      ```shell
      helm --kubeconfig ~/.kube/configs/yourkubeconfig -n auroral-node install auroral-node-chart ./manifests
      ```

   Check with `helm install -h` for help on this command or refer to the [documentation](https://helm.sh/docs/helm/helm_install/)
