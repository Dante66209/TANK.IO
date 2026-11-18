#!/usr/bin/env python3
"""Render/Docker entrypoint for TANK.IO Dedicated WebSocket Server.

Starts Godot 4.6 headless on an internal loopback port and listens on 0.0.0.0:$PORT:
- Plain HTTP GET/HEAD requests (e.g. Render health checks or browser wake-up) get HTTP 200 OK.
- WebSocket Upgrade requests are bridged transparently as raw TCP to Godot's WebSocket server.
"""

import asyncio
import os
import re
import signal
import subprocess
import sys


GODOT_BIN = os.environ.get("GODOT_BIN", "/usr/local/bin/godot")
PROJECT_PATH = os.environ.get("PROJECT_PATH", "/app")
INTERNAL_PORT = int(os.environ.get("INTERNAL_PORT", "7777"))
PUBLIC_PORT = int(os.environ.get("PORT", "10000"))

UPGRADE_RE = re.compile(rb"(?im)^upgrade:\s*websocket\b")
HEADER_END = b"\r\n\r\n"


async def pipe_stream(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
	try:
		while True:
			chunk = await reader.read(65536)
			if not chunk:
				break
			writer.write(chunk)
			await writer.drain()
	except (ConnectionError, asyncio.CancelledError, OSError):
		pass
	finally:
		try:
			if not writer.is_closing():
				writer.close()
		except OSError:
			pass


async def handle_client(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter) -> None:
	upstream_writer = None
	try:
		try:
			raw_head = await asyncio.wait_for(client_reader.readuntil(HEADER_END), timeout=10.0)
		except (asyncio.TimeoutError, asyncio.IncompleteReadError, asyncio.LimitOverrunError, ConnectionError):
			return

		if UPGRADE_RE.search(raw_head):
			try:
				up_reader, upstream_writer = await asyncio.wait_for(
					asyncio.open_connection("127.0.0.1", INTERNAL_PORT), timeout=5.0
				)
			except (ConnectionError, asyncio.TimeoutError, OSError):
				client_writer.write(b"HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
				await client_writer.drain()
				return

			upstream_writer.write(raw_head)
			await upstream_writer.drain()

			t1 = asyncio.create_task(pipe_stream(client_reader, upstream_writer))
			t2 = asyncio.create_task(pipe_stream(up_reader, client_writer))
			await asyncio.wait([t1, t2], return_when=asyncio.FIRST_COMPLETED)
			for task in (t1, t2):
				if not task.done():
					task.cancel()
					try:
						await task
					except asyncio.CancelledError:
						pass
		else:
			body = b"OK - TANK.IO Dedicated WebSocket Server running\n"
			resp = (
				b"HTTP/1.1 200 OK\r\n"
				b"Content-Type: text/plain; charset=utf-8\r\n"
				b"Cache-Control: no-store\r\n"
				+ f"Content-Length: {len(body)}\r\n".encode("ascii")
				+ b"Connection: close\r\n\r\n"
				+ body
			)
			client_writer.write(resp)
			await client_writer.drain()
	except (ConnectionError, OSError):
		pass
	finally:
		for w in (client_writer, upstream_writer):
			if w is not None and not w.is_closing():
				try:
					w.close()
				except OSError:
					pass


def build_godot_cmd() -> list[str]:
	room = os.environ.get("ROOM_NAME", "Arena Online TANK.IO")
	max_p = os.environ.get("MAX_PLAYERS", "10")
	cmd = [
		GODOT_BIN,
		"--headless",
		"--audio-driver",
		"Dummy",
		"--path",
		PROJECT_PATH,
		"--",
		"--server",
		f"--port={INTERNAL_PORT}",
		"--bind=127.0.0.1",
		f"--room={room}",
		f"--max-players={max_p}",
	]
	if os.environ.get("AUTOFILL_BOTS", "").lower() in ("1", "true", "yes"):
		cmd.append("--autofill")
	if os.environ.get("AUTO_START", "").lower() in ("1", "true", "yes"):
		cmd.append("--auto-start")
	return cmd


async def main() -> int:
	godot_cmd = build_godot_cmd()
	print(f"[PROXY] Starting Godot server on 127.0.0.1:{INTERNAL_PORT} -> public 0.0.0.0:{PUBLIC_PORT}", flush=True)
	godot_proc = subprocess.Popen(godot_cmd)

	stop_event = asyncio.Event()
	loop = asyncio.get_running_loop()
	for sig in (signal.SIGINT, signal.SIGTERM):
		try:
			loop.add_signal_handler(sig, stop_event.set)
		except NotImplementedError:
			pass

	server = await asyncio.start_server(handle_client, "0.0.0.0", PUBLIC_PORT)
	print(f"[PROXY] Listening on 0.0.0.0:{PUBLIC_PORT} (HTTP /health + WS upgrade)", flush=True)

	try:
		while not stop_event.is_set():
			rc = godot_proc.poll()
			if rc is not None:
				print(f"[PROXY] Godot process exited with code {rc}", flush=True)
				return rc
			try:
				await asyncio.wait_for(stop_event.wait(), timeout=0.5)
			except asyncio.TimeoutError:
				pass
	finally:
		server.close()
		await server.wait_closed()
		if godot_proc.poll() is None:
			godot_proc.terminate()
			try:
				godot_proc.wait(timeout=5)
			except subprocess.TimeoutExpired:
				godot_proc.kill()
	return 0


if __name__ == "__main__":
	sys.exit(asyncio.run(main()))
