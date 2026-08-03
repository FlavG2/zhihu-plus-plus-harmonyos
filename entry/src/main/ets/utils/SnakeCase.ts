type JsonValue = string | number | boolean | null | JsonValue[] | Record<string, JsonValue>;

function snakeToCamelKey(key: string): string {
  return key.replace(/_([a-z])/g, (_match: string, letter: string): string => letter.toUpperCase());
}

export function camelizeJson(value: JsonValue): JsonValue {
  if (Array.isArray(value)) {
    return value.map((item: JsonValue): JsonValue => camelizeJson(item));
  }

  if (value !== null && typeof value === 'object') {
    const next: Record<string, JsonValue> = {};
    Object.keys(value).forEach((key: string) => {
      next[snakeToCamelKey(key)] = camelizeJson(value[key]);
    });
    return next;
  }

  return value;
}
