package com.rohit.lan_mouse_mobile

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Base64
import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import kotlin.concurrent.thread

/// Text clipboard sync with the PC-side helper (clipboard_helper.py
/// in tools/), over UDP 4243: the lan-mouse protocol itself has no
/// clipboard messages. Wire format: "LMHELLO" (discovery ping),
/// "LMHERE" (PC is here), "LMCLIP <base64-utf8>" (new clipboard
/// text, either direction).
///
/// Clipboard access goes through the Lan Mouse IME: as the selected
/// input method it may read and write the system clipboard even
/// while another app is in front (Android 10+ restricts clipboard
/// access for everyone else). Loop prevention mirrors the helper:
/// remember the hash of the last text applied from the PC and never
/// send that text back.
object ClipboardSync {

    private const val PORT = 4243
    private const val MAX_TEXT_BYTES = 32768

    @Volatile
    private var running = false
    private var socket: DatagramSocket? = null

    @Volatile
    private var pcAddr: InetAddress? = null

    @Volatile
    private var lastReceivedHash = 0

    @Volatile
    private var lastSentHash = 0

    fun start() {
        if (running) return
        running = true
        thread(name = "clipboard-sync") {
            try {
                val s = DatagramSocket(PORT)
                s.broadcast = true
                socket = s
                discover()
                val buf = ByteArray(65535)
                while (running) {
                    val packet = DatagramPacket(buf, buf.size)
                    s.receive(packet)
                    handle(packet)
                }
            } catch (e: Exception) {
                if (running) {
                    Log.d("LanMouseDbg", "clipboard sync stopped: $e")
                }
            } finally {
                socket = null
            }
        }
    }

    fun stop() {
        running = false
        try {
            socket?.close()
        } catch (e: Exception) {
            // Already closed.
        }
        socket = null
    }

    /// Broadcasts a discovery ping; the helper answers LMHERE and
    /// the PC's address is learned from the reply. Retried on every
    /// Enter, so a helper started later is still found.
    fun discover() {
        val s = socket ?: return
        thread(name = "clipboard-discover") {
            try {
                val data = "LMHELLO".toByteArray(Charsets.US_ASCII)
                s.send(
                    DatagramPacket(
                        data, data.size,
                        InetAddress.getByName("255.255.255.255"), PORT,
                    ),
                )
            } catch (e: Exception) {
                // No network yet: discovery retries on Enter.
            }
        }
    }

    private fun handle(packet: DatagramPacket) {
        val msg = String(
            packet.data, packet.offset, packet.length, Charsets.US_ASCII,
        )
        when {
            msg == "LMHERE" -> pcAddr = packet.address
            msg.startsWith("LMCLIP ") -> {
                pcAddr = packet.address
                val text = try {
                    String(
                        Base64.decode(msg.substring(7), Base64.DEFAULT),
                        Charsets.UTF_8,
                    )
                } catch (e: Exception) {
                    return
                }
                lastReceivedHash = text.hashCode()
                applyToClipboard(text)
            }
        }
    }

    private fun applyToClipboard(text: String) {
        val ime = LanMouseImeService.instance
        if (ime != null) {
            ime.setClipboardText(text)
            return
        }
        val ctx = ClientInputDispatcher.appContext ?: return
        try {
            val cm = ctx.getSystemService(
                Context.CLIPBOARD_SERVICE,
            ) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("lan-mouse", text))
        } catch (e: Exception) {
            // Background write denied (Android 10+): needs the IME.
        }
    }

    /// Sends the tablet's current clipboard text to the PC. Called
    /// when the pointer leaves for the PC — the natural moment:
    /// whatever was copied while the pointer was here is what the
    /// user wants to paste over there.
    fun pushCurrentClipboard() {
        val ime = LanMouseImeService.instance ?: return
        val text = ime.getClipboardText() ?: return
        if (text.isEmpty()) return
        if (text.toByteArray(Charsets.UTF_8).size > MAX_TEXT_BYTES) return
        val h = text.hashCode()
        if (h == lastReceivedHash || h == lastSentHash) return
        lastSentHash = h
        val s = socket ?: return
        thread(name = "clipboard-push") {
            try {
                val payload = "LMCLIP " + Base64.encodeToString(
                    text.toByteArray(Charsets.UTF_8), Base64.NO_WRAP,
                )
                val data = payload.toByteArray(Charsets.US_ASCII)
                val target = pcAddr
                    ?: InetAddress.getByName("255.255.255.255")
                s.send(DatagramPacket(data, data.size, target, PORT))
            } catch (e: Exception) {
                // Best effort: the next Enter/Leave retries.
            }
        }
    }
}
