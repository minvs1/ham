# Ham

HAM (HA Addon Manager) is a simple container that can be used as an init container to automatically download, install and update Home Assistant lovelace resources and custom components.

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
    [
      {
        "name": "vacuum-card",
        "url": "https://github.com/denysdovhan/vacuum-card/releases/download/v2.10.1/vacuum-card.js",
        "version": "2.10.1",
        "type": "file",
        "install_type": "www"
      },
      {
        "name": "browser-mod",
        "url": "https://github.com/thomasloven/hass-browser_mod.git",
        "version": "2.3.0",
        "type": "git",
        "install_type": "custom_components",
        "repo_path": "browser_mod"
      },
      {
        "name": "apex-cards",
        "url": "https://github.com/RomRider/apexcharts-card/releases/download/v2.0.4/apexcharts-card.zip",
        "version": "2.0.4",
        "type": "zip",
        "install_type": "www",
        "lovelace_resource": "apex-cards/card.js"
      }
    ]
```

### Components Configuration

Each component in components.json can have the following properties:

- `name` (required): Unique identifier for the component
- `url` (required): URL to download the component from
- `version` (required): Version of the component for update tracking
- `type` (optional): Type of the file ("file", "zip", or "git"). If not specified, will be auto-detected from the URL
- `install_type` (optional): Where to install the component ("www" or "custom_components"). Defaults to "www"
- `lovelace_resource` (optional): Path to the JS file that should be added to lovelace_resources.yaml. Required for non-file type components in www directory
- `repo_path` (optional): For git repositories, specifies the subdirectory containing the component

#### Installation Types and Handling

- **Single Files (JS, CSS)**
  - Installed to `/config/www/`
  - For www installations, filename is automatically used as lovelace_resource if not specified

- **ZIP Files**
  - Extracted to `/config/www/[name]/` or `/config/custom_components/[name]/`
  - For www installations, must specify lovelace_resource pointing to the main JS file

- **Git Repositories**
  - Cloned and installed to `/config/www/[name]/` or `/config/custom_components/[name]/`
  - Use repo_path to specify which subdirectory contains the component
  - For www installations, must specify lovelace_resource

### Update your Home Assistant configuration

Add the following to your Home Assistant configuration:

```yaml
lovelace: !include lovelace_resources.yaml
```

### Add Init Container

```yaml
initContainers:
  - name: install-ham
    image: "ghcr.io/minvs1/ham:latest"
    volumeMounts:
      - name: config
        mountPath: /config
      - name: custom-components-config
        mountPath: /config/ham/components.json
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
              mountPath: /config/ham/components.json
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
docker build -f Dockerfile.test -t ham-tests .
docker run --rm ham-tests
```
