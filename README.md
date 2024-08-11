# HACS Plugins

HACS Plugins is a simple container that can be used as an init container to automatically download, install and update HACS plugins.

## ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-components-config
data:
  components.json: |
    {
      "vacuum-card": "https://github.com/denysdovhan/vacuum-card/releases/download/v2.10.1/vacuum-card.js",
      "purifier-card": "https://github.com/denysdovhan/purifier-card/releases/download/v2.6.2/purifier-card.js",
      "mini-graph-card-bundle": "https://github.com/kalkih/mini-graph-card/releases/download/v0.12.1/mini-graph-card-bundle.js",
      "card-mod": "https://raw.githubusercontent.com/thomasloven/lovelace-card-mod/v3.4.3/card-mod.js",
      "bar-card": "https://github.com/custom-cards/bar-card/releases/download/3.2.0/bar-card.js",
      "banner-card": "https://github.com/nervetattoo/banner-card/releases/download/0.13.0/banner-card.js",
      "bubble-card": "https://github.com/Clooos/Bubble-Card/blob/v2.1.1/dist/bubble-card.js",
      "dwains-dashboard": "https://raw.githubusercontent.com/dwainscheeren/dwains-lovelace-dashboard/3.0/custom_components/dwains_dashboard/js/dwains-dashboard.js"
    }
```

## Init Container

```yaml
      initContainers:
        - name: install-hacs-plugins
          image: "ghcr.io/minvs/hacs-plugins:latest"
          volumeMounts:
            - name: config
              mountPath: /config
            - name: custom-components-config
              mountPath: /config/www/components.json
              subPath: components.json
```

## Homeassistant Configuration

```yaml
lovelace:
  mode: yaml
  resources:
    - url: /local/vacuum-card.js?v=2.10.1
      type: module
    - url: /local/mini-graph-card-bundle.js?v=0.12.1
      type: module
    - url: /local/card-mod.js?v=3.4.3
      type: module
    - url: /local/bar-card.js?v=3.2.0
      type: module
    - url: /local/banner-card.js?v=0.13.0
      type: module
    - url: /local/bubble-card.js?v=2.1.1
      type: module
    - url: /local/purifier-card.js?v=2.6.2
      type: module
    - url: /local/dwains-dashboard.js?v=3.0
      type: module
```
## Example Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: home-assistant
  name: home-assistant
spec:
  template:
    metadata:
      labels:
        app: home-assistant
    spec:
      initContainers:
        - name: install-hacs-plugins
          image: "ghcr.io/minvs/hacs-plugins:latest"
          volumeMounts:
            - name: config
              mountPath: /config
            - name: custom-components-config
              mountPath: /config/www/components.json
              subPath: components.json
      containers:
        - name: home-assistant
          image: "ghcr.io/home-assistant/home-assistant:2024.7.1"
          volumeMounts:
            - name: config
              mountPath: /config
      volumes:
        - name: config
          persistentVolumeClaim:
            claimName: home-assistant-config-pvc
        - name: custom-components-config
          configMap:
            name: custom-components-config
```