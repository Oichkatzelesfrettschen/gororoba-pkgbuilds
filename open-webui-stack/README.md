# Open WebUI runtime

The package installs Open WebUI 0.13.4 and its compiled frontend under
`/opt/open-webui-stack`. Python 3.11 comes from the `python311` package.
The hash lock pins every wheel, including CPU-only PyTorch, so the UI leaves
CUDA memory available to the separately managed Ollama servers.

Build outside the recipe directory using `packaging/README.md`.
The package contains runtime files only; private data, authentication and router
credentials belong in the user's private service configuration.

Remove the package with `pacman -R open-webui-stack`; retain private application
data separately when rolling back.
