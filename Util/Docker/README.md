# CARLA Docker

This directory contains the Dockerfiles and helper scripts used to build and run
CARLA in containers:

- `Base.Dockerfile`, `Development.Dockerfile`, `CI.Dockerfile` — build/dev/CI images.
- `Release.Dockerfile`, `Runtime.Dockerfile` — ship a packaged CARLA server; both
  start it with `CMD /bin/bash CarlaUE4.sh`.
- `build.sh` / `run.sh` — convenience wrappers around `docker build` / `docker run`.

## Networking: exposing the server outside the container

> [!IMPORTANT]
> Since the server binds its listeners to `127.0.0.1` (loopback) by default, a
> CARLA container is **not reachable through published ports** (`-p`) out of the
> box. The RPC/streaming protocol has no authentication or encryption, so the
> default is loopback-only on purpose.

The server's RPC, streaming and multi-GPU listeners bind to the address given by
`--listen-host` (default `127.0.0.1`). Inside a container that means only the
container's own loopback can reach them, so Docker's port forwarding has nothing
to connect to.

To connect to the server from the host (or another container), pick one:

- **Publish ports and bind to all interfaces** — override the default `CMD` so the
  server binds to `0.0.0.0`, then publish the ports:

  ```bash
  docker run --rm -p 2000-2002:2000-2002 <carla-image> \
    /bin/bash CarlaUE4.sh --listen-host=0.0.0.0
  ```

  The client then connects to the host on port 2000:
  `carla.Client('<docker-host-ip>', 2000)`.

- **Share the host network** — the container's loopback is the host's loopback, so
  the default localhost bind already works for a host-local client:

  ```bash
  docker run --rm --net=host <carla-image>
  # client: carla.Client('127.0.0.1', 2000)
  ```

The `--listen-host` flag is also accepted via `[CARLA/Server] ListenHost` in
`CarlaSettings.ini`. The Traffic Manager RPC server always binds to `127.0.0.1`;
run the Traffic Manager in the same network namespace as its client (i.e. on the
same host / `--net=host`).
