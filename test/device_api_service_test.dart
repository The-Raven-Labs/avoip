import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/models/device_model.dart';
import 'package:authenticav/services/device_api_service.dart';

void main() {
  test('reads preview_url and stream_url from the controller device list', () {
    // Shape of GET /api/v1/devices on the controller.
    final devices = DeviceApiService.parseDevices(
      jsonDecode('''[
        {
          "id": "7752f413-f5d9-41b0-ab82-087e10c85498",
          "ip": "192.168.29.187",
          "mac": "447CAC010013",
          "hostname": "Auth-VTX-1_447CAC010013",
          "device_type": "tx",
          "status": "online",
          "current_tx_ip": null,
          "preview_url": "http://192.168.29.173:8000/api/v1/devices/7752f413-f5d9-41b0-ab82-087e10c85498/preview.jpg",
          "stream_url": "http://192.168.29.173:8000/api/v1/devices/7752f413-f5d9-41b0-ab82-087e10c85498/stream"
        },
        {
          "id": "642b504c-9ea4-4967-bc8f-bc8d06134d4c",
          "ip": "192.168.29.200",
          "mac": "447CAC020013",
          "hostname": "Auth-VRX-1_447CAC020013",
          "device_type": "rx",
          "status": "offline",
          "current_tx_ip": "192.168.29.187"
        }
      ]'''),
    );

    expect(devices, hasLength(2));

    final tx = devices[0];
    expect(tx.name, 'Auth-VTX-1_447CAC010013');
    expect(tx.type, DeviceType.tx);
    // Adopted devices use the MAC without colons as their id.
    expect(tx.mac.replaceAll(':', ''), '447CAC010013');
    expect(
      tx.previewUrl,
      'http://192.168.29.173:8000/api/v1/devices/7752f413-f5d9-41b0-ab82-087e10c85498/preview.jpg',
    );
    expect(
      tx.streamUrl,
      'http://192.168.29.173:8000/api/v1/devices/7752f413-f5d9-41b0-ab82-087e10c85498/stream',
    );

    final rx = devices[1];
    expect(rx.type, DeviceType.rx);
    expect(rx.signal, 0);
    expect(rx.previewUrl, isNull);
    expect(rx.streamUrl, isNull);
    expect(rx.currentTxIp, '192.168.29.187');
    expect(tx.currentTxIp, isNull);
  });

  test('reads selected, and link-local IPs, from the 2026-11 device list', () {
    // Shape from the brief: no router, boxes on 169.254.x.x, routed by channel.
    final devices = DeviceApiService.parseDevices(
      jsonDecode('''[
        {"id":"3f2c","ip":"169.254.54.160","mac":"447CAC020013",
         "hostname":"Auth-VRX-1_447CAC020013","device_type":"rx",
         "status":"online","last_seen":"2026-11-18T10:02:11+00:00",
         "current_tx_ip":"169.254.10.20","selected":"0032","channel":null,
         "preview_url":"http://192.168.50.1:8000/api/v1/devices/3f2c/preview.jpg",
         "stream_url":"http://192.168.50.1:8000/api/v1/devices/3f2c/stream"},
        {"id":"9a1b","ip":"169.254.10.20","mac":"447CAC010013",
         "hostname":"Auth-VTX-1_447CAC010013","device_type":"tx",
         "status":"online","current_tx_ip":null,"selected":null,
         "channel":"0032"},
        {"id":"c0de","ip":"192.168.168.115","mac":"447CAC020099",
         "device_type":"rx","status":"online",
         "current_tx_ip":"192.168.168.209","selected":"192.168.168.209"}
      ]'''),
    );

    final channelRx = devices[0];
    expect(channelRx.ip, '169.254.54.160');
    expect(channelRx.selected, '0032');
    expect(channelRx.currentTxIp, '169.254.10.20');
    expect(channelRx.channel, isNull);
    // The controller's own address, not the box's, serves the pictures.
    expect(channelRx.previewUrl, startsWith('http://192.168.50.1:8000/'));

    final tx = devices[1];
    expect(tx.channel, '0032');
    expect(tx.selected, isNull);

    // An Rx still routed the old way reports an IP.
    expect(devices[2].selected, '192.168.168.209');
  });

  test('an empty selected means nothing is selected', () {
    final devices = DeviceApiService.parseDevices([
      {'ip': '10.0.0.2', 'mac': '447CAC040013', 'device_type': 'rx', 'selected': ''},
      {'ip': '10.0.0.3', 'mac': '447CAC050013', 'device_type': 'rx'},
    ]);
    expect(devices[0].selected, isNull);
    expect(devices[1].selected, isNull);
  });

  test('skips entries without an IP and accepts a devices wrapper', () {
    final devices = DeviceApiService.parseDevices({
      'devices': [
        {'ip': '', 'mac': '447CAC030013'},
        {'ip': '192.168.29.201', 'mac': '447CAC040013', 'device_type': 'rx'},
      ],
    });
    expect(devices.map((d) => d.ip), ['192.168.29.201']);
  });
}
