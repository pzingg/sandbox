defmodule Sandbox.Firehose.CAR do
  @moduledoc """
  A module for decoding CAR files.
  """

  import Bitwise, only: [bor: 2, bsl: 2]

  require Logger

  @type cidstring() :: String.t()
  @type didstring() :: String.t()
  @type tidstring() :: String.t()

  defmodule Path do
    @moduledoc """
    A path value, split into the collection lexicon and the rkey.
    """

    @derive Jason.Encoder
    defstruct [:coll, :rkey, :rest]

    @type t() :: %__MODULE__{
            coll: String.t(),
            rkey: CAR.tidstring(),
            rest: String.t()
          }
  end

  defmodule Op do
    @moduledoc """
    An operation value.
    """

    alias Sandbox.Firehose.CAR.Path

    @derive Jason.Encoder
    defstruct [:action, :cid, :path]

    @type t() :: %__MODULE__{
            action: atom(),
            cid: CAR.cidstring(),
            path: Path.t()
          }

    def collection(op) do
      case op.path do
        %Path{coll: coll} when is_binary(coll) -> coll
        _ -> nil
      end
    end
  end

  @all_collections [
    "app.bsky.actor.profile",
    "app.bsky.feed.generator",
    "app.bsky.feed.like",
    "app.bsky.feed.post",
    "app.bsky.feed.postgate",
    "app.bsky.feed.repost",
    "app.bsky.feed.threadgate",
    "app.bsky.graph.block",
    "app.bsky.graph.follow",
    "app.bsky.graph.list",
    "app.bsky.graph.listblock",
    "app.bsky.graph.listitem",
    "app.bsky.graph.starterpack",
    "app.bsky.labeler.service",
    "chat.bsky.actor.declaration"
  ]

  @post_collections [
    "app.bsky.feed.post",
    "app.bsky.feed.repost"
  ]

  @unsafe_keys [
    "sig"
  ]

  @derive Jason.Encoder
  defstruct [:length, :roots, :version, :blocks]

  @type t() :: %__MODULE__{
          length: integer(),
          roots: [cidstring()],
          version: integer(),
          blocks: %{cidstring() => any()}
        }

  def find_post_block(%{ops: ops, blocks: %__MODULE__{blocks: blocks}} = _message) do
    case find_post_op(ops) do
      %Op{cid: cid} ->
        Map.get(blocks, cid)

      _ ->
        nil
    end
  end

  def find_post_block(_), do: nil

  def find_post_op(ops) when is_list(ops) do
    Enum.find(ops, &create_post?/1)
  end

  def find_post_op(_ops), do: nil

  def has_create_post?(ops) when is_list(ops) do
    Enum.any?(ops, &create_post?/1)
  end

  def create_post?(%Op{action: :create, path: %Path{coll: coll}}) when is_binary(coll) do
    Enum.member?(@post_collections, coll)
  end

  def create_post?(_op), do: false

  def decode_cbor!(data) do
    case CBOR.decode(data) do
      {:ok, cbor, rest} ->
        {normalize_cbor(cbor), rest}

      {:error, reason} ->
        raise ArgumentError, reason
    end
  end

  def decode_car!(data, header_only? \\ true) do
    {length, _lbytes, rest} = decode_varint!(data)

    with {%{roots: roots, version: version}, blocks} <- decode_cbor!(rest) do
      blocks =
        if header_only? do
          blocks
        else
          decode_blocks!(blocks)
        end

      %__MODULE__{length: length, roots: roots, version: version, blocks: blocks}
    else
      {invalid, _rest} ->
        raise ArgumentError, "invalid block: #{inspect(invalid)}"
    end
  end

  def decode_blocks!(data, acc \\ %{}) do
    {_len, _lbytes, rest} = decode_varint!(data)
    {cid, block_data} = decode_cid!(rest)
    {block, rest} = decode_block_data!(block_data, cid.codec)
    block =
      if is_map(block) && Map.has_key?(block, :sig) && is_binary(block.sig) do
        Map.put(block, :sig, "b64:" <> Base.encode64(block.sig, padding: false))
      else
        block
      end
    key = cid_string(cid)
    acc = Map.put(acc, key, block)

    if rest == "" do
      acc
    else
      decode_blocks!(rest, acc)
    end
  end

  def decode_block_data!(data, "dag-cbor") do
    decode_cbor!(data)
  end

  def decode_block_data!(_data, codec) do
    raise ArgumentError, "unimplemented block data for #{codec}"
  end

  def decode_cid!(data) do
    {version, vbytes, version_rest} = decode_varint!(data)
    {codec_code, cbytes, codec_rest} = decode_varint!(version_rest)

    cond do
      version == 18 && codec_code == 32 ->
        codec = "dag-cbor"
        <<digest::binary-size(32), rest::binary>> = codec_rest
        multihash = vbytes <> cbytes <> digest
        {%CID{version: 0, codec: codec, multihash: multihash}, rest}

      version == 1 ->
        codec = codec_mappings(codec_code)
        {multihash, rest} = decode_multihash!(codec_rest)
        {%CID{version: version, codec: codec, multihash: multihash}, rest}

      true ->
        raise ArgumentError, "invalid CID version #{version}"
    end
  end

  def codec_mappings(0x55), do: "raw"
  def codec_mappings(0x70), do: "dag-pb"
  def codec_mappings(0x71), do: "dag-cbor"

  def codec_mappings(codec_code) do
    raise ArgumentError, "unexpected codec_code #{codec_code}"
  end

  def decode_multihash!(data) do
    {_code, code_bytes, code_rest} = decode_varint!(data)
    {size, size_bytes, size_rest} = decode_varint!(code_rest)
    <<digest::binary-size(size), rest::binary>> = size_rest
    multihash = code_bytes <> size_bytes <> digest
    {multihash, rest}
  end

  @doc """
    Decodes LEB128 encoded bytes to an unsigned integer.

    Returns a tuple where the first element is the decoded value and the second
    element the bytes which have not been parsed.

    This function will raise `ArgumentError` if the given `b` is not a valid LEB128 integer.

      iex> decode_varint!(<<172, 2>>)
      {300, <<172, 2>>, <<>>}

      iex> decode_varint!(<<172, 2, 0>>)
      {300, <<172, 2>>, <<0>>}

      iex> decode_varint!(<<0>>)
      {0, <<0>>, <<>>}

      iex> decode_varint!(<<1>>)
      {1, <<1>>, <<>>}

      iex> decode_varint!(<<218>>)
      ** (ArgumentError) not a valid LEB128 encoded integer
  """
  @spec decode_varint!(binary) :: {non_neg_integer, binary, binary}
  def decode_varint!(b) when is_binary(b), do: do_decode_varint!(0, 0, <<>>, b)

  @spec do_decode_varint!(non_neg_integer, non_neg_integer, binary, binary) ::
          {non_neg_integer, binary, binary}
  defp do_decode_varint!(result, shift, acc, <<0::1, byte::7, rest::binary>>) do
    {bor(result, bsl(byte, shift)), acc <> <<0::1, byte::7>>, rest}
  end

  defp do_decode_varint!(result, shift, acc, <<1::1, byte::7, rest::binary>>) do
    do_decode_varint!(
      bor(result, bsl(byte, shift)),
      shift + 7,
      acc <> <<1::1, byte::7>>,
      rest
    )
  end

  defp do_decode_varint!(_result, _shift, _acc, _bin) do
    raise ArgumentError, "not a valid LEB128 encoded integer"
  end

  def decode_path!(data) do
    case String.split(data, "/") do
      [collection | [rkey | rest]] ->
        rest =
          case rest do
            nil -> nil
            [] -> nil
            _ -> Enum.join(rest, "/")
          end

        %Path{coll: collection, rkey: rkey, rest: rest}

      parts ->
        raise ArgumentError, "invalid path: #{inspect(parts)}"
    end
  end

  @doc """
  Convert string keys to atoms, and conver `%CBOR{tag: 42}` to `CID`.
  """
  @spec normalize_cbor(term()) :: term()

  def normalize_cbor(%CID{} = val) do
    cid_string(val)
  end

  def normalize_cbor(%CBOR.Tag{} = val) do
    maybe_decode_tag(val)
  end

  def normalize_cbor(val) when is_map(val) do
    Enum.reduce(val, %{}, fn {k, v}, acc ->
      Map.put(acc, String.to_atom(k), normalize_cbor(v))
    end)
  end

  def normalize_cbor(val) when is_list(val) do
    Enum.reduce(val, [], fn v, acc ->
      [normalize_cbor(v) | acc]
    end)
    |> Enum.reverse()
  end

  def normalize_cbor(val), do: val

  def maybe_decode_tag(%CBOR.Tag{tag: 42, value: %CBOR.Tag{tag: :bytes, value: cid_bytes}} = data) do
    case CID.decode_cid(cid_bytes) do
      {:ok, %CID{} = cid} ->
        cid_string(cid)

      {:error, reason} ->
        Logger.error("failed to decode CID: #{inspect(reason)}")
        data
    end
  end

  def maybe_decode_tag(%CBOR.Tag{tag: :bytes, value: bytes}) do
    bytes
  end

  def maybe_decode_tag(value), do: value

  def cid_string(%CID{} = cid), do: CID.encode!(cid)
end
