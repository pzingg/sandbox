# Sandbox

A Phoenix 1.7 / LiveView 1.0.0-rc7 testbed.

Also includes an Elixir AT (Bluesky) firehose parser, and a Python script to 
turn a firehost commit into a Graphviz diagram of the commit tree.

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix

## Anatomy of a live view

1. Root element (usually a `<div>` child created in the `<body>` element).
  Has "id" attribute with value "phx-GApxfqAkI-_sPwDG".
  Has "data-phx-root-id" the same value as "id".
  Has "data-phx-main" attribute (no value).
  Has "data-phx-session" attribute with Base64, encrypted session value.
  Has "data-phx-static" attribute with Base64 value.
  Has class attribute with value "phx-connected"

2. Flash group element (`<div>`)
  Has "id" attribute with value "flash-group"
  Has "data-phx-id" attribute "m1-phx-GApxfqAkI-_sPwDG" (magicId with cid "1")
  Has child `<div>`s with "id" attributes "client-error" and "server-error"
  Each of these have "hidden" attribute
  Each of these have "phx-connected" and "phx-disconnected" attributes with JS instructions

3. Live components (`<form>` and `<div>`)
  Has "data-phx-id" attribute "c1-phx-GApxfqAkI-_sPwDG" (magicId with cid "1")
  Has "data-phx-component" attribute with value "1"
  Has "phx-target" with value "1" (@myself)
  Has "phx-change", "phx-submit" values

## Bluesky Merkle Trees

### MST Structure

At a high level, the repository MST is a key/value mapping where the keys are non-empty byte arrays, and the values are CID links to records. The MST data structure should be fully reproducible from such a mapping of bytestrings-to-CIDs, with exactly reproducible root CID hash (aka, the `data` field in commit object).

Every node in the tree structure contains a set of key/CID mappings, as well as links to other sub-tree nodes. The entries and links are in key-sorted order, with all of the keys of a linked sub-tree (recursively) falling in the range corresponding to the link location. The sort order is from **left** (lexically first) to **right** (lexically latter). Each key has a **depth** derived from the key itself, which determines which sub-tree it ends up in. The top node in the tree contains all of the keys with the highest depth value (which for a small tree may be all depth zero, so a single node). Links to the left or right of the entire node, or between any two keys in the node, point to a sub-tree node containing keys that fall in the corresponding key range.

An empty repository with no records is represented as a single MST node with an empty array of entries. This is the only situation in which a tree may contain an empty leaf node which does not either contain keys ("entries") or point to a sub-tree containing entries. The top of the tree must not be a an empty node which only points to a sub-tree. Empty intermediate nodes are allowed, as long as they point to a sub-tree which does contain entries. In other words, empty nodes must be pruned from the top and bottom of the tree, but empty intermediate nodes must be kept, such that sub-tree links do not skip a level of depth. The overall structure and shape of the MST is deterministic based on the current key/value content, regardless of the history of insertions and deletions that lead to the current contents.

For the atproto MST implementation, the hash algorithm used is SHA-256 (binary output), counting "prefix zeros" in 2-bit chunks, giving a fanout of 4. To compute the depth of a key:

- hash the key (a byte array) with SHA-256, with binary output
- count the number of leading binary zeros in the hash, and divide by two, rounding down
- the resulting positive integer is the depth of the key

Some examples, with the given ASCII strings mapping to byte arrays:

- `2653ae71`: depth "0"
- `blue`: depth "1"
- `app.bsky.feed.post/454397e440ec`: depth "4"
- `app.bsky.feed.post/9adeb165882c`: depth "8"

There are many MST nodes in repositories, so it is important that they have a compact binary representation, for storage efficiency. Within every node, keys (byte arrays) are compressed by eliding common prefixes, with each entry indicating how many bytes it shares with the previous key in the array. The first entry in the array for a given node must contain the full key, and a common prefix length of 0. This key compaction is internal to nodes, it does not extend across multiple nodes in the tree. The compaction scheme is mandatory, to ensure that the MST structure is deterministic across implementations.

The node IPLD schema fields are:
  - `l` ("left", CID link, optional): link to sub-tree Node on a lower level and with all keys sorting before keys at this node
  - `e` ("entries", array of objects, required): ordered list of TreeEntry objects

The TreeEntry schema fields are:
  - `p` ("prefixlen", integer, required): count of bytes shared with previous TreeEntry in this Node (if any)
  - `k` ("keysuffix", byte array, required): remainder of key for this TreeEntry, after "prefixlen" have been removed
  - `v` ("value", CID Link, required): link to the record data (CBOR) for this entry
  - `t` ("tree", CID Link, optional): link to a sub-tree Node at a lower level which has keys sorting after this TreeEntry's key (to the "right"), but before the next TreeEntry's key in this Node (if any)

When parsing MST data structures, the depth and sort order of keys should be verified. This is particularly true for untrusted inputs, but is simplest to just verify every time. Additional checks on node size and other parameters of the tree structure also need to be limited; see the "Security Considerations" section of this document.

  
```elixir
defmodule NodeData do
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

  "app.bsky.feed.post/3laf7splhud26"
  "b25ndt3qc2m"  
  """
  
  defstruct [:p, :k, :v, :t]
end


```