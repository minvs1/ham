# HACS Plugins

HACS Plugins is a simple container that can be used as an init container to automatically download, install and update HACS plugins.

## Getting Started

### Create a components.json file

Your components.json file defines which plugins to install and how they should be loaded. Here's an example using a ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-components-config
data:
  components.json: |
    {
      "vacuum-card": {
        "url": "https://github.com/denysdovhan/vacuum-card/releases/download/v2.10.1/vacuum-card.js",
        "version": "2.10.1",
        "lovelace_resource": "vacuum-card.js"
      },
      "browser_mod": {
        "url": "https://github.com/thomasloven/hass-browser_mod/releases/download/2.3.0/browser_mod.js",
        "version": "2.3.0",
        "lovelace_resource": null
      },
      "apex-cards": {
        "url": "https://github.com/RomRider/apexcharts-card/releases/download/v2.0.4/apexcharts-card.zip",
        "version": "2.0.4",
        "lovelace_resource": "apexcharts-card/card.js"
      }
    }
```

### Components Configuration

Each component in components.json can have the following properties:

- `url` (required): URL to download the component from
- `version` (required): Version of the component for update tracking
- `type` (optional): Type of the file ("js" or "zip"). If not specified, will be auto-detected from the URL
- `lovelace_resource` (optional): Path to the JS file that should be added to lovelace_resources.yaml. Set to null for components that don't need to be added to Lovelace resources

#### File Types and Handling

- **JavaScript Files (.js)**
  - Downloaded directly to `/config/www/[name].js`
  - Set `lovelace_resource` to the desired JS filename

- **ZIP Files (.zip)**
  - Automatically extracted to `/config/www/[zip-name]/`
  - Set `lovelace_resource` to point to the main JS file within the extracted directory

### Update your Home Assistant configuration

Add the following to your Home Assistant configuration:

```yaml
lovelace: !include lovelace_resources.yaml
```

### Add Init Container

```yaml
      initContainers:
        - name: install-hacs-plugins
          image: "ghcr.io/minvs1/hacs-plugins:latest"
          volumeMounts:
            - name: config
              mountPath: /config
            - name: custom-components-config
              mountPath: /config/www/components.json
              subPath: components.json
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
          image: "ghcr.io/minvs1/hacs-plugins:latest"
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

## Version Management

The container maintains a lock file (`components.json.lock`) to track installed versions. Components are only downloaded when:
- They haven't been installed before
- A new version is specified in components.json

## Tests

```bash
docker build -f Dockerfile.test -t hacs-plugins-tests .
docker run --rm hacs-plugins-tests
```
