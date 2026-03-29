// ignore_for_file: constant_identifier_names

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/widgets.dart';

/// 全局图标映射：保持 `Icons.xxx` 调用方式不变，底层统一替换为 FontAwesome。
class Icons {
  Icons._();
  static const IconData code = FontAwesomeIcons.code;
  static const IconData auto_graph_outlined = FontAwesomeIcons.chartLine;
  static const IconData favorite_outline = FontAwesomeIcons.heart;
  static const IconData library_books_outlined = FontAwesomeIcons.bookOpen;
  static const IconData link_outlined = FontAwesomeIcons.link;
  static const IconData meeting_room_outlined = FontAwesomeIcons.doorOpen;
  static const IconData new_releases_outlined = FontAwesomeIcons.star;
  static const IconData support_agent_outlined = FontAwesomeIcons.headset;
  static const IconData verified_outlined = FontAwesomeIcons.circleCheck;
  static const IconData new_releases = FontAwesomeIcons.arrowsRotate;
  static const IconData verified_user_outlined = FontAwesomeIcons.shieldHalved;
}
