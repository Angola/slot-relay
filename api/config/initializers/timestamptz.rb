# frozen_string_literal: true

# datetime カラムを timestamp ではなく timestamptz で作る。
#
# reservations の排他制約は tstzrange(start_at, end_at, '[)') を GiST インデックスに使う。
# カラムが timestamp（タイムゾーンなし）だと timestamptz への暗黙キャストが必要になり、
# そのキャストは TimeZone 設定に依存する＝STABLE 扱いなので
# 「functions in index expression must be marked IMMUTABLE」でインデックスを作れない。
ActiveSupport.on_load(:active_record_postgresqladapter) do
  self.datetime_type = :timestamptz
end
