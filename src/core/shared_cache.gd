class_name SharedCache
extends RefCounted
## 여러 스레드가 함께 쓰는 읽기 결과 저장소. 게임을 켜면 배경 스레드(AssetPreloader)가 모델·소리 꾸러미를 미리 읽어
## 여기에 넣고, 게임(주 스레드)은 여기서 꺼내 쓴다. 같은 것을 두 스레드가 동시에 찾으면 나중에 온 쪽이 먼저 온 쪽이
## 다 읽기를 기다렸다가 그 결과를 쓴다(두 번 읽지 않는다). 못 읽은 결과(null)도 기억해 다시 읽지 않는다.
##
## 주의: loader 안에서 렌더링 서버가 답을 돌려주는 호출(ImageTexture.get_image 등)을 하면 안 된다. 배경 스레드의 그런
## 호출은 주 스레드가 다음 프레임을 그릴 때까지 기다리는데, 주 스레드가 여기서 그 스레드를 기다리고 있으면 둘 다 멈춘다.

var _mutex := Mutex.new()
var _values := {}
## 키 → 그 키를 지금 읽는 스레드가 잡고 있는 자물쇠
var _key_locks := {}


## key의 값. 아직 없으면 loader를 불러 읽고 기억한다.
func get_or_load(key: String, loader: Callable) -> Variant:
	_mutex.lock()
	if _values.has(key):
		var found: Variant = _values[key]
		_mutex.unlock()
		return found
	var key_lock := _key_locks.get(key) as Mutex
	if key_lock == null:
		key_lock = Mutex.new()
		_key_locks[key] = key_lock
	_mutex.unlock()
	key_lock.lock()
	_mutex.lock()
	var ready := _values.has(key)
	var value: Variant = _values.get(key)
	_mutex.unlock()
	if not ready:
		value = loader.call()
		_mutex.lock()
		_values[key] = value
		_key_locks.erase(key)
		_mutex.unlock()
	key_lock.unlock()
	return value


## 이미 읽어 둔 것이 있는지 (읽는 중이면 false)
func has(key: String) -> bool:
	_mutex.lock()
	var found := _values.has(key)
	_mutex.unlock()
	return found


## 읽어 둔 값. 없으면 fallback.
func peek(key: String, fallback: Variant = null) -> Variant:
	_mutex.lock()
	var value: Variant = _values.get(key, fallback)
	_mutex.unlock()
	return value


## 읽어 둔 것의 수 (테스트용)
func size() -> int:
	_mutex.lock()
	var count := _values.size()
	_mutex.unlock()
	return count


## 읽어 둔 것을 모두 잊는다 (테스트용)
func clear() -> void:
	_mutex.lock()
	_values.clear()
	_mutex.unlock()
