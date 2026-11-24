package com.example.authenticavgkb

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // See lib/services/network_binding.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.authenticav/network")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindToWifi" -> result.success(bindToWifi())
                    "release" -> {
                        bindProcessTo(null)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // The SC-1's hotspot has no internet, so Android may send the app's
    // traffic over mobile data. Pin the process to the Wi-Fi network instead.
    private fun bindToWifi(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        @Suppress("DEPRECATION")
        val wifi: Network? = manager.allNetworks.firstOrNull { network ->
            manager.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
        if (wifi == null) {
            // Nothing to pin to: don't keep a binding to a Wi-Fi that's gone.
            bindProcessTo(null)
            return false
        }
        return manager.bindProcessToNetwork(wifi)
    }

    private fun bindProcessTo(network: Network?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        manager.bindProcessToNetwork(network)
    }
}
