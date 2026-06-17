/// A single photo of a tank, taken on a given day. Up to 3 are allowed per
/// tank per day. The image file lives in the private `tank-photos` storage
/// bucket; [storagePath] points to it and [signedUrl] is a short-lived URL
/// used to display it (resolved by the repository when listing).
class TankPhoto {
  const TankPhoto({
    required this.id,
    required this.tankId,
    required this.storagePath,
    required this.takenOn,
    this.signedUrl,
  });

  final String id;
  final String tankId;
  final String storagePath;

  /// The calendar day the photo counts against (local date).
  final DateTime takenOn;

  /// Short-lived URL for displaying the image; null until resolved.
  final String? signedUrl;

  /// Max photos a user can upload for a single tank on a single day.
  static const int dailyLimit = 3;

  factory TankPhoto.fromJson(Map<String, dynamic> json) => TankPhoto(
        id: json['id'] as String,
        tankId: json['tank_id'] as String,
        storagePath: json['storage_path'] as String,
        takenOn: DateTime.parse(json['taken_on'] as String),
      );

  TankPhoto copyWith({String? signedUrl}) => TankPhoto(
        id: id,
        tankId: tankId,
        storagePath: storagePath,
        takenOn: takenOn,
        signedUrl: signedUrl ?? this.signedUrl,
      );

  /// True when this photo was taken on [day] (compared by calendar date).
  bool isOn(DateTime day) =>
      takenOn.year == day.year &&
      takenOn.month == day.month &&
      takenOn.day == day.day;
}
