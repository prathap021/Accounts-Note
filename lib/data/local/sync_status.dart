/// Where a locally-stored record stands with respect to the cloud.
///
/// Every record in Hive carries one of these. The UI reads it directly, so a
/// user can always tell whether what they typed has left the device.
enum SyncStatus {
  /// Written to Firestore and confirmed.
  synced,

  /// Queued locally, waiting for a connection or for its turn in the queue.
  pending,

  /// Currently being pushed.
  syncing,

  /// Pushing failed repeatedly. The local data is intact and will be retried.
  failed;

  static SyncStatus fromName(String? name) => SyncStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => SyncStatus.pending,
      );

  bool get isSettled => this == SyncStatus.synced;
}

/// The cloud write a pending record still owes.
///
/// Deletes are tombstoned rather than removed outright, so an offline delete
/// survives an app restart and still reaches Firestore later.
enum PendingOp {
  none,
  create,
  update,
  delete;

  static PendingOp fromName(String? name) => PendingOp.values.firstWhere(
        (o) => o.name == name,
        orElse: () => PendingOp.none,
      );
}
