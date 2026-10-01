import { Capacitor } from '@capacitor/core';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// A stand-in for the native bridge: records listeners so a test can emit events
// and see which handles were removed.
const bridge = vi.hoisted(() => {
  type Listener = { event: string; fn: (data: unknown) => void; remove: () => Promise<void> };
  const listeners: Listener[] = [];
  return {
    listeners,
    emit(event: string, data: unknown) {
      listeners.filter((l) => l.event === event).forEach((l) => l.fn(data));
    },
    plugin: {
      create: vi.fn(async () => undefined),
      destroy: vi.fn(async () => undefined),
      onResize: vi.fn(),
      onDisplay: vi.fn(),
      onScroll: vi.fn(),
      addListener: vi.fn(async (event: string, fn: (data: unknown) => void) => {
        const listener: Listener = {
          event,
          fn,
          remove: vi.fn(async () => {
            listeners.splice(listeners.indexOf(listener), 1);
          }),
        };
        listeners.push(listener);
        return listener;
      }),
    },
  };
});

vi.mock('./implementation', () => ({ CapacitorAppleMaps: bridge.plugin }));

// Imported after the mock is registered. Running under vitest's `node`
// environment (no HTMLElement / customElements) also covers the SSR import.
const { AppleMap } = await import('./map');

const observers: { disconnect: ReturnType<typeof vi.fn> }[] = [];

function makeElement(): HTMLElement {
  return {
    dataset: {},
    getBoundingClientRect: () => ({ x: 0, y: 0, width: 100, height: 100 }),
  } as unknown as HTMLElement;
}

function createMap(id = 'map-1') {
  return AppleMap.create({ id, element: makeElement(), config: { center: { lat: 0, lng: 0 }, zoom: 10 } });
}

beforeEach(() => {
  bridge.listeners.length = 0;
  observers.length = 0;
  vi.spyOn(Capacitor, 'isNativePlatform').mockReturnValue(true);
  vi.stubGlobal('window', {
    devicePixelRatio: 2,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  });
  vi.stubGlobal(
    'ResizeObserver',
    class {
      disconnect = vi.fn();
      observe = vi.fn();
      constructor() {
        observers.push(this);
      }
    },
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  bridge.plugin.create.mockReset();
});

describe('module import', () => {
  it('does not require DOM globals', () => {
    expect(typeof HTMLElement).toBe('undefined');
    expect(AppleMap).toBeDefined();
  });
});

describe('AppleMap.create', () => {
  it('detaches its observers when native creation fails', async () => {
    bridge.plugin.create.mockRejectedValueOnce(new Error('native create failed'));

    await expect(createMap()).rejects.toThrow('native create failed');

    expect(observers).toHaveLength(1);
    expect(observers[0].disconnect).toHaveBeenCalledOnce();
    const added = vi.mocked(window.addEventListener).mock.calls;
    const removed = vi.mocked(window.removeEventListener).mock.calls;
    expect(added).toHaveLength(2);
    expect(removed).toEqual(added);
  });
});

describe('setOnMapReadyListener', () => {
  it('replaces the previous listener and clears it when called without a callback', async () => {
    const map = await createMap();
    const first = vi.fn();
    const second = vi.fn();

    await map.setOnMapReadyListener(first);
    await map.setOnMapReadyListener(second);
    bridge.emit('onMapReady', { mapId: 'map-1' });
    expect(first).not.toHaveBeenCalled();
    expect(second).toHaveBeenCalledOnce();

    await map.setOnMapReadyListener();
    bridge.emit('onMapReady', { mapId: 'map-1' });
    expect(second).toHaveBeenCalledOnce();
    expect(bridge.listeners).toHaveLength(0);
  });

  it('ignores ready events for other maps', async () => {
    const map = await createMap();
    const callback = vi.fn();
    await map.setOnMapReadyListener(callback);

    bridge.emit('onMapReady', { mapId: 'other' });
    expect(callback).not.toHaveBeenCalled();
  });

  it('is removed by destroy so a recreated map with the same id is not double-notified', async () => {
    const map = await createMap();
    const callback = vi.fn();
    await map.setOnMapReadyListener(callback);

    await map.destroy();
    bridge.emit('onMapReady', { mapId: 'map-1' });

    expect(callback).not.toHaveBeenCalled();
    expect(bridge.listeners).toHaveLength(0);
  });
});
