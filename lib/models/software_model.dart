/// 软件模型
class Software {
  final String id;
  final String name;
  final String? description;
  final int byte;
  final String downloadURL;
  final List<String> commands;
  final List<Attachment> attachments;
  final String? xxh64;
  final String? cate4; // 用于 servers 和 databases
  final List<Extension>? exts; // 用于 php
  final bool skipunzip; // 是否跳过解压

  Software({
    required this.id,
    required this.name,
    this.description,
    required this.byte,
    required this.downloadURL,
    required this.commands,
    required this.attachments,
    this.xxh64,
    this.cate4,
    this.exts,
    this.skipunzip = false,
  });

  factory Software.fromJson(Map<String, dynamic> json) {
    return Software(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      byte: json['byte'] as int,
      downloadURL: json['downloadURL'] as String,
      commands:
          (json['commands'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      attachments:
          (json['attachments'] as List<dynamic>?)
              ?.map((e) => Attachment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      xxh64: json['xxh64'] as String?,
      cate4: json['cate4'] as String?,
      exts: (json['exts'] as List<dynamic>?)
          ?.map((e) => Extension.fromJson(e as Map<String, dynamic>))
          .toList(),
      skipunzip: json['skipunzip'] as bool? ?? false,
    );
  }
}

/// 附件模型
class Attachment {
  final String downloadURL;
  final List<String> commands;

  Attachment({required this.downloadURL, required this.commands});

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      downloadURL: json['downloadURL'] as String,
      commands: (json['commands'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );
  }
}

/// 扩展模型（用于 PHP 扩展）
class Extension {
  final String name;
  final String downloadURL;

  Extension({required this.name, required this.downloadURL});

  factory Extension.fromJson(Map<String, dynamic> json) {
    return Extension(
      name: json['name'] as String,
      downloadURL: json['downloadURL'] as String,
    );
  }
}

/// 软件源模型
class SoftwareSource {
  final String? mirrorURL;
  final List<Software> servers;
  final List<Software> databases;
  final List<Software> php;
  final List<Software> tools;
  final String? phpCgiSpawner; // php-cgi-spawner 下载地址
  final String? phpCmd; // php-cmd (php.bat) 下载地址

  SoftwareSource({
    this.mirrorURL,
    required this.servers,
    required this.databases,
    required this.php,
    required this.tools,
    this.phpCgiSpawner,
    this.phpCmd,
  });

  factory SoftwareSource.fromJson(Map<String, dynamic> json) {
    return SoftwareSource(
      mirrorURL: json['mirrorURL'] as String?,
      servers:
          (json['servers'] as List<dynamic>?)
              ?.map((e) => Software.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      databases:
          (json['databases'] as List<dynamic>?)
              ?.map((e) => Software.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      php:
          (json['php'] as List<dynamic>?)
              ?.map((e) => Software.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tools:
          (json['tools'] as List<dynamic>?)
              ?.map((e) => Software.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      phpCgiSpawner: json['php-cgi-spawner'] as String?,
      phpCmd: json['php-cmd'] as String?,
    );
  }
}
