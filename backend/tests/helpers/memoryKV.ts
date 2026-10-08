export function memoryKV() {
  const store = new Map<string, string>()
  const kv = {
    get: async (key: string) => store.get(key) ?? null,
    put: async (key: string, value: string) => {
      store.set(key, value)
    },
    delete: async (key: string) => {
      store.delete(key)
    },
  } as unknown as KVNamespace
  const blockKeys = () => [...store.keys()].filter((key) => key.startsWith('plan-block:'))
  return { kv, blockKeys, store }
}
