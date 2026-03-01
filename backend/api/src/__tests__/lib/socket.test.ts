import { locationRoom, overlappingRooms } from '../../lib/socket';

describe('socket geo-grid helpers', () => {
  describe('locationRoom', () => {
    it('maps a coordinate to a 0.1-degree grid cell', () => {
      const room = locationRoom(40.7128, -74.006);
      expect(room).toBe('location:40.7:-74.1');
    });

    it('maps zero to location:0.0:0.0', () => {
      expect(locationRoom(0, 0)).toBe('location:0.0:0.0');
    });

    it('handles negative coordinates', () => {
      const room = locationRoom(-33.85, 151.21);
      expect(room).toBe('location:-33.9:151.2');
    });

    it('snaps to grid boundary', () => {
      expect(locationRoom(40.7, -74.0)).toBe('location:40.7:-74.0');
      expect(locationRoom(40.79, -73.91)).toBe('location:40.7:-74.0');
    });

    it('places slightly different coords in same room', () => {
      const a = locationRoom(40.71, -74.005);
      const b = locationRoom(40.75, -74.02);
      expect(a).toBe(b);
    });
  });

  describe('overlappingRooms', () => {
    it('returns a 3x3 grid of rooms (up to 9)', () => {
      const rooms = overlappingRooms(40.75, -74.05);
      expect(rooms.length).toBeGreaterThanOrEqual(9);
      expect(rooms.length).toBeLessThanOrEqual(9);
    });

    it('includes the center room', () => {
      const center = locationRoom(40.75, -74.05);
      const rooms = overlappingRooms(40.75, -74.05);
      expect(rooms).toContain(center);
    });

    it('includes diagonal neighbours', () => {
      const rooms = overlappingRooms(40.75, -74.05);
      expect(rooms).toContain('location:40.6:-74.1');
      expect(rooms).toContain('location:40.8:-74.0');
    });

    it('deduplicates when on grid boundary', () => {
      const rooms = overlappingRooms(40.7, -74.0);
      const unique = new Set(rooms);
      expect(unique.size).toBe(rooms.length);
    });
  });
});
