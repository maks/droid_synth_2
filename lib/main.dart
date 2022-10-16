import 'package:bonsai/bonsai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';


void main() {
  if (kDebugMode) {
    Log.init();
  }
  runApp(const App());
}
