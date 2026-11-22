// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SharedState _$SharedStateFromJson(Map<String, dynamic> json) => _SharedState(
  setupParams: json['setupParams'] == null
      ? null
      : SetupParams.fromJson(json['setupParams'] as Map<String, dynamic>),
  vpnOptions: json['vpnOptions'] == null
      ? null
      : VpnOptions.fromJson(json['vpnOptions'] as Map<String, dynamic>),
  stopTip: json['stopTip'] as String,
  startTip: json['startTip'] as String,
  localNetworkTip: json['localNetworkTip'] as String,
  currentProfileName: json['currentProfileName'] as String,
  stopText: json['stopText'] as String,
  showStopAction: json['showStopAction'] as bool? ?? true,
  currentServer: json['currentServer'] as String? ?? '',
  pingText: json['pingText'] as String? ?? '',
  showPing: json['showPing'] as bool? ?? false,
  pingServers:
      (json['pingServers'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  detail: json['detail'] as String? ?? '',
  stats: json['stats'] as String? ?? '',
);

Map<String, dynamic> _$SharedStateToJson(_SharedState instance) =>
    <String, dynamic>{
      'setupParams': instance.setupParams,
      'vpnOptions': instance.vpnOptions,
      'stopTip': instance.stopTip,
      'startTip': instance.startTip,
      'localNetworkTip': instance.localNetworkTip,
      'currentProfileName': instance.currentProfileName,
      'stopText': instance.stopText,
      'showStopAction': instance.showStopAction,
      'currentServer': instance.currentServer,
      'pingText': instance.pingText,
      'showPing': instance.showPing,
      'pingServers': instance.pingServers,
      'detail': instance.detail,
      'stats': instance.stats,
    };
