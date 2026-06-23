# active_model_serializers 0.10 config (migrated from 0.9, which the app's serializers were written
# against). The :json adapter wraps each serialized resource in a root key (e.g. {"assessment": {...}})
# — the behavior the serializer specs expect from 0.9. key_transform :unaltered keeps snake_case keys.
ActiveModelSerializers.config.adapter = :json
ActiveModelSerializers.config.key_transform = :unaltered
