#!/usr/bin/python3

import html
import json
import os
import re
import subprocess
import sys
import tempfile
from hashlib import sha256

class Graph:
  def __init__(self, thread, output=sys.stdout):
    self.thread = thread
    self.file = output
    self.null_id = 1
    self.nodes = []
    self.edges = []
    self.ids = []

  def add_node(self, id, dot_node):
    if id and id not in self.ids:
      self.ids.append(id)
      self.nodes.append(dot_node)

  def add_edge(self, id_from, id_to, color = 'black'):
    if id_from and id_to:
      edge = f'{id_from} -> {id_to} [color={color}]'
      if edge not in self.edges:
        self.edges.append(edge)

  @staticmethod
  def post_label(post):
    rkey = html.escape(post['uri'].split('/')[-1])
    author = html.escape(post['author']['handle'])
    text = html.escape(post['record']['text'][:30])
    return f'<<table border="0"><tr><td>{rkey}</td></tr><tr><td>{author}</td></tr><tr><td>{text}</td></tr></table>>'

  @staticmethod
  def post_color(post):
    author = post['author']['handle']
    if author == 'katewagner.bsky.social':
      return 'red'
    else:
      return 'black'

  @staticmethod
  def post_id(post):
    id = post['uri'].replace('at://did:', '').replace('app.bsky.feed.post/', '')
    return re.sub(r'[^-_0-9A-Za-z]+', '_', id)

  def add_parent(self, post, parent):
    if post is None or parent is None:
      return

    parent_post = parent.get('post')
    if parent_post is None:
      return

    self.make_node(parent_post)
    id_from = Graph.post_id(parent_post)
    id_to = Graph.post_id(post)
    self.add_edge(id_from, id_to, 'red')
    self.add_parent(parent_post, parent.get('parent'))
    self.add_replies(parent_post, parent.get('replies', []))

  def add_replies(self, post, replies):
    if post is None:
      return

    for reply in replies:
      reply_post = reply.get('post')
      if reply_post:
        self.make_node(reply_post)
        id_from = Graph.post_id(post)
        id_to = Graph.post_id(reply_post)
        self.add_edge(id_from, id_to, 'green')
        self.add_parent(reply_post, reply.get('parent'))
        self.add_replies(reply_post, reply.get('replies', []))

  def make_tree(self):
    post = self.thread.get('post')
    self.make_node(post)
    self.add_parent(post, self.thread.get('parent'))
    self.add_replies(post, self.thread.get('replies', []))

    print('digraph { rankdir=LR', file=self.file)
    for node in self.nodes:
      print(node, file=self.file)
    for edge in self.edges:
      print(edge, file=self.file)
    print('}', file=self.file)

  def make_node(self, post):
    if post is None:
      return

    label = Graph.post_label(post)
    id = Graph.post_id(post)
    color = Graph.post_color(post)
    dot_node = f'{id} [shape=box color={color} label={label}]'
    self.add_node(id, dot_node)

  @staticmethod
  def write_thread_diagram(thread, o):
    graph = Graph(thread, output=o)
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
  thread = json.load(f)['thread']
  f.close()

  Graph.write_thread_diagram(thread, o)
  if oname:
    o.close()

  if format != 'dot':
    cmd = ['dot', f'-T{format}', f'-o{args.output}', oname]
    print(' '.join(cmd))
    result = subprocess.run(cmd)
    if result.returncode == 0:
      print(f'deleting {oname}')
      os.remove(oname)
