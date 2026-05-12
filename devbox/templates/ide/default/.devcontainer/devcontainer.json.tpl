{
  "name": "{{ .Project.Prefix }} {{ .Project.Name }} {{ .Service }}",
  "dockerComposeFile": [
    "../../../compose.yaml"{{ range .ServiceCfg.Compose }},
    "../../../{{ . }}"{{ end }}
  ],
  "service": "{{ .ServiceCfg.Container }}",
  "runServices": ["{{ .ServiceCfg.Container }}"],
  "workspaceFolder": "{{ .ServiceCfg.DirInternal }}",
  "remoteUser": "www-data",
  "updateRemoteUserUID": false,
  "customizations": {
    "vscode": {
      "extensions": [
        "xdebug.php-debug",
        "bmewburn.vscode-intelephense-client",
        "mikestead.dotenv"
      ],
      "settings": {
        "php.validate.executablePath": "/usr/local/bin/php"
      }
    }
  }
}
