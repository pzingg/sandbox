# Sandbox

A Phoenix 1.7 / LiveView 1.0 testbed for Bluesky.

Features: 

- Elixir client for Bluesky OAuth2, app password authentication, and xrpc requests
- Bluesky timeline view in Phoenix
- Bluesky firehose client and parser in Elixir
- Python script to turn a firehost commit into a Graphviz diagram of the commit tree

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Configuration

Enable `ngrok` (must be installed on your development machine) support in config.exs:

- `:ngrok_envs` - mix environments that will use ngrok

```Elixir
config :sandbox, ngrok_envs: [:dev, :test]
```

Set up various Bluesky settings in config.exs:

- `:timezone` - to show timeline in local time instead of UTC
- `:client_type` (default `:public`) - set to :confidential to use client assertions in OAuth client
- `:client_scope` (default `"atproto transition:generic"`)
- `:app_password_file` - file path to a JSON file for app password login

```Elixir
config :sandbox, Sandbox.Bluesky,
  timezone: "America/Los_Angeles",
  client_type: :public,
  client_scope: "atproto transition:generic"
  app_password_file: "/path-to-file.json"
```

The JSON app password file (used for tests only) must contain these keys:

- `"did"` - your did
- `"handle"` - your "bsky.social" handle
- `"app_password"` - your registered app password
- `"pds_url"` - normally set to "https://bsky.social"

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix

## Bluesky firehose

The project has code to start a WebSocket client connection to the Bluesky
firehose in the `Bluesky.Firehose` modules, using native Elixir decoders
for CIDs and CAR "files".

To subscribe to the Bluesky Firehose, call this somewhere in your code:

```ELixir
Sandbox.Bluesky.WebsocketClient.start(stream: :repos)
```

## Bluesky OAuth client authentication

The project has code to authenticate to a Bluesky Authorization Server
according to the Bluesky documentation, [here](https://atproto.com/specs/oauth) and 
[here](https://docs.bsky.app/docs/advanced-guides/oauth-client),
using details ported from the 
[Bluesky Python OAuth demonstration web app]( https://github.com/bluesky-social/cookbook/tree/main/python-oauth-web-app).

The code uses the `dpop` branch in a 
[fork of the OAuth2 Elixir library](https://github.com/pzingg/oauth2).
This fork adds new fields to the `OAuth2.Client` struct to handle the
[Pushed Authorization Requests](https://docs.bsky.app/docs/advanced-guides/oauth-client#par) 
and [DPoP](https://docs.bsky.app/docs/advanced-guides/oauth-client#dpop) 
request and response headers used in Bluesky's OAuth specification.

The SandboxWeb Phoenix application provides the necessary callback, client 
metadata and JWKS endpoints.

## Bluesky app password client authentication

Bluesky [app password](https://lifehacker.com/tech/why-you-should-be-using-bluesky-app-passwords) 
authentication is used in tests. See the Configuration section above for 
how to create and configure an app password file once you have obtained 
an app password.

## Bluesky timeline

The Sandbox.Feed module contains decoders for the `getTimeline` XRPC
call, and there is a minimal Phoenix Live View UI that displays the 
decoded timeline.

## Bluesky XRPC requests

Three different modes are used for XRPC requests: unauthenticated,
authenticated with a Bearer access token retrieved with the 
`"com.atproto.server.createSession"` request, and authenticated with 
a DPoP token and nonce after OAuth2 authorization.

### Rate limiting errors

The code checks for rate limit errors in XRPC responses, where:

- `response.status_code == 429`
- `response.body["error"] == "RateLimitExceeded"`
- `response.body["message"] == "Rate Limit Exceeded"`, and
- `response.headers` will have a member `{"ratelimit-reset", [timestamp]}`
  where timestamp is the UNIX epoch time at which the request can be resumed

### Token expiration errors

If the access token for XRPC calls has expired, the response will have: 

- `response.status_code == 401`
- `response.body["error"] == "invalid_token"` and
- `response.body["message"] == "\"exp\" claim timestamp check failed"`

Currently, the code does not automatically attempt to refresh 
an expired access token. The "Refresh token" button on the "/account" page 
can be used to update the acces token. (TODO!)

## Bluesky Merkle Trees

From the Bluesky documentation:

At a high level, the repository MST is a key/value mapping where the keys are 
non-empty byte arrays, and the values are CID links to records. The MST data 
structure should be fully reproducible from such a mapping of 
bytestrings-to-CIDs, with exactly reproducible root CID hash (aka, the 
`"data"` field in commit object).

Every node in the tree structure contains a set of key/CID mappings, as well 
as links to other sub-tree nodes. The entries and links are in key-sorted 
order, with all of the keys of a linked sub-tree (recursively) falling in the 
range corresponding to the link location. The sort order is from **left** 
(lexically first) to **right** (lexically latter). Each key has a **depth** 
derived from the key itself, which determines which sub-tree it ends up in. 
The top node in the tree contains all of the keys with the highest depth 
value (which for a small tree may be all depth zero, so a single node). Links
to the left or right of the entire node, or between any two keys in the node, 
point to a sub-tree node containing keys that fall in the corresponding key 
range.

An empty repository with no records is represented as a single MST node with 
an empty array of entries. This is the only situation in which a tree may 
contain an empty leaf node which does not either contain keys ("entries") or 
point to a sub-tree containing entries. The top of the tree must not be a an
empty node which only points to a sub-tree. Empty intermediate nodes are 
allowed, as long as they point to a sub-tree which does contain entries. 
In other words, empty nodes must be pruned from the top and bottom of the 
tree, but empty intermediate nodes must be kept, such that sub-tree links 
do not skip a level of depth. The overall structure and shape of the MST is 
deterministic based on the current key/value content, regardless of the 
history of insertions and deletions that lead to the current contents.

For the atproto MST implementation, the hash algorithm used is SHA-256 
(binary output), counting "prefix zeros" in 2-bit chunks, giving a fanout 
of 4. To compute the depth of a key:

- hash the key (a byte array) with SHA-256, with binary output
- count the number of leading binary zeros in the hash, and divide by two, 
  rounding down
- the resulting positive integer is the depth of the key

Some examples, with the given ASCII strings mapping to byte arrays:

- `"2653ae71"`: depth "0"
- `"blue"`: depth "1"
- `"app.bsky.feed.post/454397e440ec"`: depth "4"
- `"app.bsky.feed.post/9adeb165882c"`: depth "8"

There are many MST nodes in repositories, so it is important that they have
a compact binary representation, for storage efficiency. Within every node, 
keys (byte arrays) are compressed by eliding common prefixes, with each 
entry indicating how many bytes it shares with the previous key in the array.
The first entry in the array for a given node must contain the full key,
and a common prefix length of 0. This key compaction is internal to nodes, 
it does not extend across multiple nodes in the tree. The compaction scheme
is mandatory, to ensure that the MST structure is deterministic across 
implementations.

The `Node` IPLD schema fields are:

  - `"l"` ("left", CID link, optional): link to sub-tree Node on a lower level 
    and with all keys sorting before keys at this node
  - `"e"` ("entries", array of objects, required): ordered list of `TreeEntry` 
    objects

The `TreeEntry` schema fields are:

  - `"p"` ("prefixlen", integer, required): count of bytes shared with previous 
    TreeEntry in this Node (if any)
  - `"k"` ("keysuffix", byte array, required): remainder of key for this 
    TreeEntry, after "prefixlen" have been removed
  - `"v"` ("value", CID Link, required): link to the record data (CBOR) for 
    this entry
  - `"t"` ("tree", CID Link, optional): link to a sub-tree `Node` at a lower 
    level which has keys sorting after this `TreeEntry`'s key (to the "right"),
    but before the next `TreeEntry`'s key in this `Node` (if any)

When parsing MST data structures, the depth and sort order of keys should be 
verified. This is particularly true for untrusted inputs, but is simplest to 
just verify every time. Additional checks on node size and other parameters 
of the tree structure also need to be limited.
  
```elixir
defmodule Node do
  @moduledoc """
    - `:l` - left (CID | nil)
    - `:e` - entries (list(TreeEntry))
  """

  defstruct [:l, :e]
end

defmodule TreeEntry do 
  @moduledoc """
    - `:p` - prefixlen (u64)
    - `:k` - keysuffix (binary)
    - `:v` - value (CID)
    - `:t` - tree (CID | nil)

  Examples of `:k`

  `"app.bsky.feed.post/3laf7splhud26"`
  `"b25ndt3qc2m"`
  """
  
  defstruct [:p, :k, :v, :t]
end


```