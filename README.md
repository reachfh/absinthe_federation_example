# AbsintheFederationExample

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix

## Rover CLI

Rover is a CLI for managing and maintaining graphs.

https://www.apollographql.com/docs/rover/

```command
brew install rover
```

## Fetch GraphQL server's schema via introspection
```console
rover graph introspect http://api.example.com/graphql > api.graphql
rover graph introspect http://api2.example.com/graphql > api2.graphql
```

## Compose a federated supergraph schema from multiple subgraphs

Create a `supergraph.yml` config file which identifies the back end servers
and graphs:

```yaml
federation_version: 2
subgraphs:
  api:
    routing_url: https://api.example.com/
    schema:
      file: ./api.graphql
  api2:
    routing_url: https://api2.example.com/
    schema:
      file: ./api2.graphql
```

Create output supergraph schema:

```console
rover supergraph compose --config ./supergraph.yml > supergraph.graphql
```

## Start Apollo Router

```console
docker-compose up apollo-router
```

## Query router

```console
curl --request POST --header 'content-type: application/json' --url 'http://0.0.0.0:4000/' --data '{"query":"query { foo }"}'
```

## Links
* https://www.apollographql.com/docs/router/
https://www.apollographql.com/docs/rover/commands/supergraphs/
* https://romankudryashov.com/blog/2022/07/apollo-router/
