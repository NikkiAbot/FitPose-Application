import '../../core/fsm_base.dart';

class ShoulderPressFSM extends RepFSM {
  ShoulderPressFSM() : super(loweredThresh: 90.0, raisedThresh: 160.0);
}
