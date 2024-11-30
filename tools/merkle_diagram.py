#!/usr/bin/python3

import json
import os
import subprocess
import sys
import tempfile
from hashlib import sha256

# From https://atproto.com/specs/repository
#
# Every node in the tree structure contains a set of key/CID mappings,
# as well as links to other sub-tree nodes. The entries and links are
# in key-sorted order, with all of the keys of a linked sub-tree
# (recursively) falling in the range corresponding to the link location.
# The sort order is from left (lexically first) to right (lexically latter).
# Each key has a depth derived from the key itself, which determines which
# sub-tree it ends up in. The top node in the tree contains all of the keys
# with the highest depth value (which for a small tree may be all depth
# zero, so a single node). Links to the left or right of the entire node,
# or between any two keys in the node, point to a sub-tree node containing
# keys that fall in the corresponding key range.
#
# An empty repository with no records is represented as a single MST node
# with an empty array of entries. This is the only situation in which a
# tree may contain an empty leaf node which does not either contain keys
# ("entries") or point to a sub-tree containing entries. The top of the
# tree must not be a an empty node which only points to a sub-tree. Empty
# intermediate nodes are allowed, as long as they point to a sub-tree
# which does contain entries. In other words, empty nodes must be pruned
# from the top and bottom of the tree, but empty intermediate nodes must
# be kept, such that sub-tree links do not skip a level of depth. The
# overall structure and shape of the MST is deterministic based on the
# current key/value content, regardless of the history of insertions and
# deletions that lead to the current contents.
#
# For the atproto MST implementation, the hash algorithm used is SHA-256
# (binary output), counting "prefix zeros" in 2-bit chunks, giving a
# fanout of 4. To compute the depth of a key:
#
#   1. hash the key (a byte array) with SHA-256, with binary output
#   2. count the number of leading binary zeros in the hash, and divide by
#     two, rounding down the resulting positive integer is the depth of the key

class Graph:
  def __init__(self, root, blocks, ops, output=sys.stdout):
    self.root = root
    self.blocks = blocks
    self.ops = ops
    self.file = output
    self.null_id = 1
    self.nodes = []
    self.edges = []
    self.ids = []

  def add_node(self, id, dot_node):
    if id not in self.ids:
      self.ids.append(id)
      self.nodes.append(dot_node)

  def add_edge(self, id_from, port_from, id_to, port_to, color = 'black'):
    if id_from:
      if port_from:
        id_from = f'{id_from}:{port_from}'
      if port_to:
        id_to = f'{id_to}:{port_to}'
      edge = f'{id_from} -> {id_to} [color={color}]'
      if edge not in self.edges:
        self.edges.append(edge)

  def make_tree(self):
    dot_roots = f'roots [shape="circle"]'
    self.add_node('roots', dot_roots)
    self.make_node('roots', None, self.root)
    dot_ops = f'ops [shape="circle"]'
    self.add_node('ops', dot_ops)
    for index, op in enumerate(self.ops):
      self.add_edge('ops', None, f'op{index}', 'a')
      self.make_op_node(op, index)
    for cid in self.blocks:
      self.make_node(None, None, cid)

    print('digraph { rankdir=LR', file=self.file)
    for node in self.nodes:
      print(node, file=self.file)
    for edge in self.edges:
      print(edge, file=self.file)
    print('}', file=self.file)

  def make_node(self, parent, port, cid, color='black'):
    if cid:
      node = self.blocks.get(cid)
      if node:
        if 'l' in node:
          self.make_tree_node(cid, parent, port, node, color)
        elif 'data' in node:
          self.make_data_node(cid, parent, port, node, color)
        elif '$type' in node:
          self.make_content_node(cid, parent, port, node, color)
        else:
          print(f'Whoa! {json.dumps(node)}', file=sys.stderr)
          sys.exit(1)
      else:
        self.make_missing_node(cid, parent, port, color)
    else:
      self.make_null_node(parent, port, color)

  def make_tree_node(self, cid, parent, port, node, color):
    elems = node['e']
    if len(elems) > 0:
      assert elems[0]['p'] == 0
      base_key = elems[0]['k']
      elems_label = ' | '.join([Graph.elem_label(base_key, index, elem) for index, elem in enumerate(elems)])
    else:
      elems_label = 'empty'

    title = f'{cid[-4:]}'
    dot_node = f'{cid} [shape="record" label="<t>{title} | <l>l | {{ {elems_label} }}"]'
    self.add_node(cid, dot_node)
    self.add_edge(parent, port, cid, 't', color)

    if node['l']:
      self.make_node(cid, 'l', node['l'])
    for index, elem in enumerate(elems):
      if elem['v']:
        self.make_node(cid, f'e{index}:s', elem['v'], 'red')
      if elem['t']:
        self.make_node(cid, f'e{index}:s', elem['t'])

  def make_data_node(self, cid, parent, port, node, color):
    title = f'{cid[-4:]}'
    did = node['did']
    signed = node.get('sig')
    if signed:
      signed = 'signed'
    else:
      signed = 'unsigned'
    dot_node = f'{cid} [shape="record" color="{color}" label="<t>{title} | {did} | {signed}"]'
    self.add_node(cid, dot_node)
    self.add_edge(parent, port, cid, 't', color)

    if node['data']:
      self.make_node(cid, 't', node['data'], 'red')

  def make_content_node(self, cid, parent, port, node, color):
    type = node['$type'].split('.')[-1]
    title = f'{cid[-4:]} {type}'
    text = node.get('text', '')
    reply = node.get('reply')
    if reply:
      reply = f"reply to: {reply['parent']['uri']}"
    embed = node.get('embed')
    if embed:
      etype = embed.get('$type')
      if etype == 'app.bsky.embed.record':
        embed = f"quote: {embed['record']['uri']}"
      elif etype == 'app.bsky.embed.recordWithMedia':
        embed = f"quote: {embed['record']['record']['uri']} with media"
      elif etype == 'app.bsky.embed.images':
        embed = f"images: {len(embed['images'])} images"
      elif etype == 'app.bsky.embed.video':
        embed = 'video'
      elif etype == 'app.bsky.embed.external':
        embed = f"preview: {embed['external']['title']} at {embed['external']['uri']}"
      else:
        embed = 'embed {etype}'
    dot_node = f'{cid} [shape="record" color="{color}" label="<t>{title} | text: {text}'
    if reply:
      dot_node += f'| {reply}'
    if embed:
      dot_node += f'| {embed}'
    dot_node += '"]'
    self.add_node(cid, dot_node)
    self.add_edge(parent, port, cid, 't', color)

  def make_missing_node(self, cid, parent, port, color):
    title = cid[-4:]
    type = 'external node'
    if color == 'red':
      type = 'external data'
    dot_node = f'{cid} [shape="record" color="{color}" label="<t>{title} | {type}"]'
    self.add_node(cid, dot_node)
    self.add_edge(parent, port, cid, 't', color)

  def make_null_node(self, parent, port, color):
    id = f'null{self.null_id}'
    self.null_id += 1
    dot_node = f'{id} [shape="record" color="{color}" label="null"]'
    self.add_node(id, dot_node)
    self.add_edge(parent, port, id, None, color)

  def make_op_node(self, op, index):
    action = op['action']
    coll = op['path']['coll'].split('.')[-1]
    rkey = op['path']['rkey'][-4:]
    id = f'op{index}'
    dot_node = f'{id} [shape="record" label="<a>op {action} | <c>{coll}/{rkey}"]'
    self.add_node(id, dot_node)
    self.make_node(id, 'c', op['cid'], 'red')

  @staticmethod
  def elem_label(base_key, index, elem):
    rkey = Graph.elem_rkey(base_key, elem)
    # depth = Graph.merkle_depth(rkey)
    desc = rkey.split('/', 2)
    if len(desc) >= 1:
      type = desc[0].split('.')[-1]
    else:
      type = "?"
    if len(desc) >= 2:
      tid = desc[1][-4:]
    else:
      tid = "?"
    return f'<e{index}>e{index}\\n{type}/{tid}'

  @staticmethod
  def elem_rkey(base_key, elem):
    rkey = elem['k']
    prefix_len = elem['p']
    if prefix_len:
      rkey = base_key[0:prefix_len] + rkey
    return rkey

  @staticmethod
  def merkle_depth(rkey):
    depth = 0
    hash_bytes = sha256(bytes(rkey, 'utf-8')).digest()
    for index, b in enumerate(hash_bytes):
      if b != 0:
        depth = (index + 1) // 2
        break

    # print(f'# {rkey} depth {depth} hash {hash_bytes}', file=sys.stderr)
    return depth

  @staticmethod
  def write_merkle_tree_diagram(commit, o):
    root = commit['blocks']['roots'][0]
    blocks = commit['blocks']['blocks']
    ops = commit['ops']

    graph = Graph(root, blocks, ops, output=o)
    graph.make_tree()

if __name__ == '__main__':
  import argparse

  def ext_to_format(ext):
    if 'ext' == '.pdf':
      return 'ps2'
    return ext[1:]

  parser = argparse.ArgumentParser()
  parser.add_argument('-f', '--file', help='input JSON file path. if omitted, use stdin')
  parser.add_argument('-o', '--output', help='output file path, with extension (.dot, .png, .svg, .pdf). if omitted, output dot to stdout')
  args = parser.parse_args()
  if args.output:
    ext = os.path.splitext(args.output)[1]
    format = ext_to_format(ext)
  else:
    format = 'dot'

  if format == 'dot':
    if args.output:
      o = open(args.output, 'w')
      oname = args.output
    else:
      o = sys.stdout
      oname = None
  else:
    o = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.dot')
    oname = o.name

  if args.file:
    f = open(args.file)
  else:
    f = sys.stdin
  commit = json.load(f)
  f.close()

  Graph.write_merkle_tree_diagram(commit, o)
  if oname:
    o.close()

  if format != 'dot':
    cmd = ['dot', f'-T{format}', f'-o{args.output}', oname]
    print(' '.join(cmd))
    result = subprocess.run(cmd)
    if result.returncode == 0:
      print(f'deleting {oname}')
      os.remove(oname)
