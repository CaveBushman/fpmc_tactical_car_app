import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const meshtasticServiceUuid = '6ba1b218-15a8-461f-9fa8-5dcae273eafd';
const meshtasticToRadioUuid = 'f75c76d2-129e-4dad-a1dd-7866124401e7';
const meshtasticFromRadioUuid = '2c55e69e-4993-11ed-b878-0242ac120002';
const meshtasticFromNumUuid = 'ed9da18c-a800-4f66-a670-aa7547e34453';

class MeshtasticBlePacket {
  const MeshtasticBlePacket({
    required this.bytes,
    required this.receivedAt,
  });

  final List<int> bytes;
  final DateTime receivedAt;
}

class MeshtasticBleState {
  const MeshtasticBleState({
    required this.status,
    this.deviceName,
    this.lastPacketAt,
    this.lastError,
  });

  final MeshtasticBleStatus status;
  final String? deviceName;
  final DateTime? lastPacketAt;
  final String? lastError;

  MeshtasticBleState copyWith({
    MeshtasticBleStatus? status,
    String? deviceName,
    DateTime? lastPacketAt,
    String? lastError,
  }) {
    return MeshtasticBleState(
      status: status ?? this.status,
      deviceName: deviceName ?? this.deviceName,
      lastPacketAt: lastPacketAt ?? this.lastPacketAt,
      lastError: lastError,
    );
  }

  static const idle = MeshtasticBleState(status: MeshtasticBleStatus.idle);
}

enum MeshtasticBleStatus {
  idle,
  scanning,
  connecting,
  connected,
  disconnected,
  error,
}

class MeshtasticBleService {
  MeshtasticBleService();

  final StreamController<MeshtasticBleState> _stateController = StreamController.broadcast();
  final StreamController<MeshtasticBlePacket> _packetController = StreamController.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _fromNumSubscription;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _toRadio;
  BluetoothCharacteristic? _fromRadio;
  MeshtasticBleState _state = MeshtasticBleState.idle;

  Stream<MeshtasticBleState> get stateStream => _stateController.stream;
  Stream<MeshtasticBlePacket> get packets => _packetController.stream;
  MeshtasticBleState get state => _state;

  Future<void> startAutoConnect({Duration timeout = const Duration(seconds: 12)}) async {
    await stopScan();
    _setState(const MeshtasticBleState(status: MeshtasticBleStatus.scanning));

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (final result in results) {
        final advertisesMeshtastic = result.advertisementData.serviceUuids.any(
          (uuid) => uuid.str.toLowerCase() == meshtasticServiceUuid,
        );
        if (!advertisesMeshtastic) {
          continue;
        }
        await stopScan();
        await connect(result.device);
        return;
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(meshtasticServiceUuid)],
        timeout: timeout,
      );
    } catch (error) {
      _setState(MeshtasticBleState(status: MeshtasticBleStatus.error, lastError: error.toString()));
    }
  }

  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    _setState(MeshtasticBleState(status: MeshtasticBleStatus.connecting, deviceName: _deviceLabel(device)));
    try {
      _device = device;
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );
      final services = await device.discoverServices();
      final meshService = services.firstWhere(
        (service) => service.uuid.str.toLowerCase() == meshtasticServiceUuid,
      );

      _toRadio = _findCharacteristic(meshService, meshtasticToRadioUuid);
      _fromRadio = _findCharacteristic(meshService, meshtasticFromRadioUuid);
      final fromNum = _findCharacteristic(meshService, meshtasticFromNumUuid);

      await fromNum.setNotifyValue(true);
      _fromNumSubscription = fromNum.lastValueStream.listen((_) => readQueuedPackets());
      await readQueuedPackets();
      _setState(MeshtasticBleState(status: MeshtasticBleStatus.connected, deviceName: _deviceLabel(device)));
    } catch (error) {
      _setState(MeshtasticBleState(status: MeshtasticBleStatus.error, deviceName: _deviceLabel(device), lastError: error.toString()));
    }
  }

  Future<void> disconnect() async {
    await _fromNumSubscription?.cancel();
    _fromNumSubscription = null;
    await _device?.disconnect();
    _device = null;
    _toRadio = null;
    _fromRadio = null;
    _setState(const MeshtasticBleState(status: MeshtasticBleStatus.disconnected));
  }

  Future<void> readQueuedPackets() async {
    final fromRadio = _fromRadio;
    if (fromRadio == null) {
      return;
    }

    final bytes = await fromRadio.read();
    if (bytes.isEmpty) {
      return;
    }
    final packet = MeshtasticBlePacket(bytes: bytes, receivedAt: DateTime.now());
    _packetController.add(packet);
    _setState(_state.copyWith(status: MeshtasticBleStatus.connected, lastPacketAt: packet.receivedAt));
  }

  Future<void> writeToRadio(List<int> protobufBytes) async {
    final toRadio = _toRadio;
    if (toRadio == null) {
      throw StateError('Meshtastic ToRadio characteristic is not connected.');
    }
    await toRadio.write(protobufBytes, withoutResponse: false);
  }

  Future<void> dispose() async {
    await stopScan();
    await disconnect();
    await _stateController.close();
    await _packetController.close();
  }

  BluetoothCharacteristic _findCharacteristic(BluetoothService service, String uuid) {
    return service.characteristics.firstWhere(
      (characteristic) => characteristic.uuid.str.toLowerCase() == uuid,
    );
  }

  String _deviceLabel(BluetoothDevice device) {
    final platformName = device.platformName.trim();
    if (platformName.isNotEmpty) {
      return platformName;
    }
    return device.remoteId.str;
  }

  void _setState(MeshtasticBleState value) {
    _state = value;
    _stateController.add(value);
  }
}
