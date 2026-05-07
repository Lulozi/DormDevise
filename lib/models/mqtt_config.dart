/// MQTT 连接与订阅所需配置的封装类：包含连接信息、认证、证书路径、
/// 命令主题与状态主题等字段，并提供默认配置、存储映射与校验接口。
class MqttConfig {
  /// MQTT 服务器地址。
  final String host;

  /// MQTT 服务器端口。
  final int port;

  /// 开门指令使用的主题。
  final String commandTopic;

  /// MQTT 客户端标识。
  final String clientId;

  /// 登录用户名，可为空。
  final String? username;

  /// 登录密码，可为空。
  final String? password;

  /// 是否启用 TLS。
  final bool withTls;

  /// CA 证书路径。
  final String caPath;

  /// 客户端证书路径，可为空。
  final String? certPath;

  /// 客户端私钥路径，可为空。
  final String? keyPath;

  /// 私钥密码，可为空。
  final String? keyPassword;

  /// 状态主题名称，可为空。
  final String? statusTopic;

  /// 是否启用状态订阅。
  final bool statusEnabled;

  /// 自定义开门消息内容。
  final String customMessage;

  const MqttConfig({
    required this.host,
    required this.port,
    required this.commandTopic,
    required this.clientId,
    required this.username,
    required this.password,
    required this.withTls,
    required this.caPath,
    required this.certPath,
    required this.keyPath,
    required this.keyPassword,
    required this.statusTopic,
    required this.statusEnabled,
    required this.customMessage,
  });

  /// 生成用于初始化的默认配置，避免出现空值或非法字段。
  factory MqttConfig.defaults() => const MqttConfig(
    host: '',
    port: 1883,
    commandTopic: '',
    clientId: '',
    username: null,
    password: null,
    withTls: false,
    caPath: 'assets/certs/ca.pem',
    certPath: null,
    keyPath: null,
    keyPassword: null,
    statusTopic: null,
    statusEnabled: false,
    customMessage: 'OPEN',
  );

  /// 从持久化存储（Map）构建 `MqttConfig` 实例，并对字段做必要的格式/空值处理。
  factory MqttConfig.fromStorage(Map<String, Object?> storage) {
    final String host = (storage['mqtt_host'] as String? ?? '').trim();
    final String topic = (storage['mqtt_topic'] as String? ?? '').trim();
    final int port =
        int.tryParse((storage['mqtt_port'] as String? ?? '1883')) ?? 1883;
    final String clientId = (storage['mqtt_clientId'] as String? ?? '').trim();
    final String username = (storage['mqtt_username'] as String? ?? '').trim();
    final String password = (storage['mqtt_password'] as String? ?? '').trim();
    final String caPath =
        (storage['mqtt_ca'] as String? ?? 'assets/certs/ca.pem').trim();
    final String certPath = (storage['mqtt_cert'] as String? ?? '').trim();
    final String keyPath = (storage['mqtt_key'] as String? ?? '').trim();
    final String keyPwd = (storage['mqtt_key_pwd'] as String? ?? '').trim();
    final String statusTopic = (storage['mqtt_status_topic'] as String? ?? '')
        .trim();
    final bool statusEnabled = storage['mqtt_status_enabled'] as bool? ?? false;
    final bool withTls = storage['mqtt_with_tls'] as bool? ?? false;
    final String customMessage =
        (storage['custom_open_msg'] as String? ?? 'OPEN').trim();
    return MqttConfig(
      host: host,
      port: port,
      commandTopic: topic,
      clientId: clientId,
      username: username.isEmpty ? null : username,
      password: password.isEmpty ? null : password,
      withTls: withTls,
      caPath: caPath.isEmpty ? 'assets/certs/ca.pem' : caPath,
      certPath: certPath.isEmpty ? null : certPath,
      keyPath: keyPath.isEmpty ? null : keyPath,
      keyPassword: keyPwd.isEmpty ? null : keyPwd,
      statusTopic: statusTopic.isEmpty ? null : statusTopic,
      statusEnabled: statusEnabled,
      customMessage: customMessage.isEmpty ? 'OPEN' : customMessage,
    );
  }

  /// 将配置序列化为 Map，便于写入 SharedPreferences 或其他 KV 存储。
  Map<String, Object?> toStorageMap() {
    return <String, Object?>{
      'mqtt_host': host,
      'mqtt_port': port.toString(),
      'mqtt_topic': commandTopic,
      'mqtt_clientId': clientId,
      'mqtt_username': username,
      'mqtt_password': password,
      'mqtt_with_tls': withTls,
      'mqtt_ca': caPath,
      'mqtt_cert': certPath,
      'mqtt_key': keyPath,
      'mqtt_key_pwd': keyPassword,
      'mqtt_status_topic': statusTopic,
      'mqtt_status_enabled': statusEnabled,
      'custom_open_msg': customMessage,
    };
  }

  /// 判断用于发送开门指令的最少参数是否已经准备完成（host 与 topic）。
  bool get isCommandReady => host.isNotEmpty && commandTopic.isNotEmpty;

  /// 判断状态订阅是否具备启用条件（需要开启状态订阅且存在有效的 statusTopic）。
  bool get isStatusReady =>
      statusEnabled && statusTopic != null && statusTopic!.isNotEmpty;

  /// 返回包含关键字段（host、port、clientId 等）的指纹字符串，便于比较或复用连接。
  String buildFingerprint({bool includeStatusTopic = false}) {
    final buffer = StringBuffer()
      ..write(host)
      ..write('|')
      ..write(port)
      ..write('|')
      ..write(clientId)
      ..write('|')
      ..write(username ?? '')
      ..write('|')
      ..write(password ?? '')
      ..write('|')
      ..write(withTls ? '1' : '0')
      ..write('|')
      ..write(certPath ?? '')
      ..write('|')
      ..write(keyPath ?? '');
    if (includeStatusTopic) {
      buffer
        ..write('|')
        ..write(statusTopic ?? '');
    }
    return buffer.toString();
  }

  /// 复制当前实例并替换所提供字段，返回新的 `MqttConfig` 实例。
  MqttConfig copyWith({
    String? host,
    int? port,
    String? commandTopic,
    String? clientId,
    String? username,
    String? password,
    bool? withTls,
    String? caPath,
    String? certPath,
    String? keyPath,
    String? keyPassword,
    String? statusTopic,
    bool? statusEnabled,
    String? customMessage,
  }) {
    return MqttConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      commandTopic: commandTopic ?? this.commandTopic,
      clientId: clientId ?? this.clientId,
      username: username == null
          ? this.username
          : (username.isEmpty ? null : username),
      password: password == null
          ? this.password
          : (password.isEmpty ? null : password),
      withTls: withTls ?? this.withTls,
      caPath: caPath ?? this.caPath,
      certPath: certPath == null
          ? this.certPath
          : (certPath.isEmpty ? null : certPath),
      keyPath: keyPath == null
          ? this.keyPath
          : (keyPath.isEmpty ? null : keyPath),
      keyPassword: keyPassword == null
          ? this.keyPassword
          : (keyPassword.isEmpty ? null : keyPassword),
      statusTopic: statusTopic == null
          ? this.statusTopic
          : (statusTopic.isEmpty ? null : statusTopic),
      statusEnabled: statusEnabled ?? this.statusEnabled,
      customMessage: customMessage == null || customMessage.isEmpty
          ? this.customMessage
          : customMessage,
    );
  }
}
