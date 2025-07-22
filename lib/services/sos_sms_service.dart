import 'package:telephony/telephony.dart';


class SosSmsService {
  final Telephony _telephony = Telephony.instance;

  Future<void> sendSmsToMultiple(List<String> numbers, String message) async {
    bool? granted = await _telephony.requestPhoneAndSmsPermissions;

    if (granted == true) {
      for (final number in numbers) {
        await _telephony.sendSms(to: number, message: message);
      }
    } else {
      throw Exception("SMS permission not granted.");
    }
  }

}
