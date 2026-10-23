import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'from_radio_drainer.dart';
import 'meshtastic_message_encoder.dart';

const meshtasticServiceUuid = '6ba1b218-15a8-461f-9fa8-5dcae273eafd';
const meshtasticToRadioUuid = 'f75c76d2-129e-4dad-a1dd-7866124401e7';
const meshtasticFromRadioUuid = '2c55e69e-4993-11ed-b878-0242ac120002';
const meshtasticFromNumUuid = 'ed9da18c-a800-4f66-a670-aa7547e34453';

class MeshtasticBlePacket {
  const MeshtasticBlePacket({required this.bytes, required this.receivedAt});

  final List<int> bytes;
  final DateTime receivedAt;
}

class MeshtasticBleState {
  const MeshtasticBleState({
    required this.status,
    this.deviceName,
    this.lastPacketAt,
    this.lastError,
    this.reconnectAttempt = 0,
  });

  final MeshtasticBleStatus status;
  final String? deviceName;
  final DateTime? lastPacketAt;
  final String? lastError;
  final int reconnectAttempt;

  MeshtasticBleState copyWith({
    MeshtasticBleStatus? status,
    String? deviceName,
    DateTime? lastPacketAt,
    String? lastError,
    int? reconnectAttempt,
  }) {
    return MeshtasticBleState(
      status: status ?? this.status,
      deviceName: deviceName ?? this.deviceName,
      lastPacketAt: lastPacketAt ?? this.lastPacketAt,
      lastError: lastError,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
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
  MeshtasticBleService({
    this.encoder = const MeshtasticMessageEncoder(),
    math.Random? random,
  }) : _random = random ?? math.Random.secure();

  static const _maxReconnectDelay = Duration(seconds: 30);

  final MeshtasticMessageEncoder encoder;
  final math.Random _random;
  final StreamController<MeshtasticBleState> _stateController =
      StreamController.broadcast();
  final StreamController<MeshtasticBlePacket> _packetController =
      StreamController.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _fromNumSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  Timer? _reconnectTimer;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _toRadio;
  FromRadioDrainer? _drainer;
  bool _userDisconnected = false;
  int _reconnectAttempt = 0;
  MeshtasticBleState _state = MeshtasticBleState.idle;

  Stream<MeshtasticBleState> get stateStream => _stateController.stream;
  Stream<MeshtasticBlePacket> get packets => _packetController.stream;
  MeshtasticBleState get state => _state;

  Future<void> startAutoConnect({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    await stopScan();
    _cancelReconnect();
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
      _setState(
        MeshtasticBleState(
          status: MeshtasticBleStatus.error,
          lastError: error.toString(),
        ),
      );
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
    _userDisconnected = false;
    _cancelReconnect();
    await _releaseLink();
    _setState(
      MeshtasticBleState(
        status: MeshtasticBleStatus.connecting,
        deviceName: _deviceLabel(device),
        reconnectAttempt: _reconnectAttempt,
      ),
    );
    try {
      _device = device;
      // mtu is Android-only and ignored elsewhere; Meshtastic packets need
      // far more than the default 23 byte MTU.
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
        mtu: 512,
        autoConnect: false,
      );
      final services = await device.discoverServices();
      final meshService = services.firstWhere(
        (service) => service.uuid.str.toLowerCase() == meshtasticServiceUuid,
      );

      _toRadio = _findCharacteristic(meshService, meshtasticToRadioUuid);
      final fromRadio = _findCharacteristic(
        meshService,
        meshtasticFromRadioUuid,
      );
      final fromNum = _findCharacteristic(meshService, meshtasticFromNumUuid);
      final drainer = FromRadioDrainer(
        read: fromRadio.read,
        onPacket: _emitPacket,
      );
      _drainer = drainer;

      await fromNum.setNotifyValue(true);
      _fromNumSubscription = fromNum.lastValueStream.listen((_) {
        unawaited(_drainSafely());
      });

      // Without want_config the radio never sends MyNodeInfo or its node DB,
      // so the app would not know its own node number or existing peers.
      await writeToRadio(
        encoder.encodeWantConfig(_random.nextInt(0x7FFFFFFF) + 1),
      );
      await drainer.drain();

      _connectionSubscription = device.connectionState.listen((
        connectionState,
      ) {
        if (connectionState == BluetoothConnectionState.disconnected) {
          _onLinkLost(device);
        }
      });
      _reconnectAttempt = 0;
      _setState(
        MeshtasticBleState(
          status: MeshtasticBleStatus.connected,
          deviceName: _deviceLabel(device),
        ),
      );
    } catch (error) {
      _setState(
        MeshtasticBleState(
          status: MeshtasticBleStatus.error,
          deviceName: _deviceLabel(device),
          lastError: error.toString(),
          reconnectAttempt: _reconnectAttempt,
        ),
      );
      if (_reconnectAttempt > 0) {
        _scheduleReconnect(device);
      }
    }
  }

  Future<void> disconnect() async {
    _userDisconnected = true;
    _cancelReconnect();
    _reconnectAttempt = 0;
    await _releaseLink();
    await _device?.disconnect();
    _device = null;
    _setState(
      const MeshtasticBleState(status: MeshtasticBleStatus.disconnected),
    );
  }

  Future<void> readQueuedPackets() => _drainSafely();

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

  Future<void> _drainSafely() async {
    final drainer = _drainer;
    if (drainer == null) {
      return;
    }
    try {
      await drainer.drain();
    } catch (error) {
      _setState(_state.copyWith(lastError: error.toString()));
    }
  }

  void _emitPacket(List<int> bytes) {
    final packet = MeshtasticBlePacket(
      bytes: bytes,
      receivedAt: DateTime.now(),
    );
    _packetController.add(packet);
    _setState(_state.copyWith(lastPacketAt: packet.receivedAt));
  }

  void _onLinkLost(BluetoothDevice device) {
    if (_userDisconnected) {
      return;
    }
    unawaited(_releaseLink());
    _setState(
      MeshtasticBleState(
        status: MeshtasticBleStatus.disconnected,
        deviceName: _deviceLabel(device),
        lastPacketAt: _state.lastPacketAt,
        lastError: 'Spojení s T-Beamem ztraceno, obnovuji.',
        reconnectAttempt: _reconnectAttempt,
      ),
    );
    _scheduleReconnect(device);
  }

  void _scheduleReconnect(BluetoothDevice device) {
    if (_userDisconnected || _reconnectTimer != null) {
      return;
    }
    _reconnectAttempt++;
    final seconds = math.min(
      _maxReconnectDelay.inSeconds,
      1 << math.min(_reconnectAttempt, 5),
    );
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      unawaited(connect(device));
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _releaseLink() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _fromNumSubscription?.cancel();
    _fromNumSubscription = null;
    _toRadio = null;
    _drainer = null;
  }

  BluetoothCharacteristic _findCharacteristic(
    BluetoothService service,
    String uuid,
  ) {
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
    if (!_stateController.isClosed) {
      _stateController.add(value);
    }
  }
}
