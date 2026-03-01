import { broadcastNewReport, broadcastNewComment, broadcastUpvote } from '../../lib/broadcast';
import * as socketModule from '../../lib/socket';

jest.mock('../../lib/socket');

const mockIO = {
  to: jest.fn().mockReturnThis(),
  emit: jest.fn(),
};

beforeEach(() => {
  jest.clearAllMocks();
  (socketModule.getIO as jest.Mock).mockReturnValue(mockIO);
  (socketModule.overlappingRooms as jest.Mock).mockReturnValue([
    'location:40.7:-74.1',
    'location:40.7:-74.0',
  ]);
});

describe('broadcastNewReport', () => {
  const fakeReport = {
    id: 'r-1',
    type: 'theft',
    lat: 40.7128,
    lng: -74.006,
    description: 'Stolen bike',
    upvotes: 0,
    comment_count: 0,
    created_at: new Date('2025-01-01'),
  };

  it('emits report:new to all overlapping rooms', () => {
    broadcastNewReport(fakeReport);

    expect(socketModule.overlappingRooms).toHaveBeenCalledWith(40.7128, -74.006);
    expect(mockIO.to).toHaveBeenCalledTimes(2);
    expect(mockIO.emit).toHaveBeenCalledWith('report:new', expect.objectContaining({ id: 'r-1' }));
  });

  it('does not throw when getIO fails', () => {
    (socketModule.getIO as jest.Mock).mockImplementation(() => {
      throw new Error('not initialised');
    });

    expect(() => broadcastNewReport(fakeReport)).not.toThrow();
  });
});

describe('broadcastNewComment', () => {
  const fakeComment = {
    id: 'c-1',
    report_id: 'r-1',
    device_id: 'device-1',
    content: 'Watch out!',
    created_at: new Date('2025-01-02'),
  };

  it('emits comment:new to the report room', () => {
    broadcastNewComment(fakeComment);

    expect(mockIO.to).toHaveBeenCalledWith('report:r-1');
    expect(mockIO.emit).toHaveBeenCalledWith(
      'comment:new',
      expect.objectContaining({ id: 'c-1', content: 'Watch out!' }),
    );
  });

  it('does not include device_id in the emitted payload', () => {
    broadcastNewComment(fakeComment);

    const payload = mockIO.emit.mock.calls[0][1];
    expect(payload).not.toHaveProperty('device_id');
  });
});

describe('broadcastUpvote', () => {
  it('emits report:upvote to the report room', () => {
    broadcastUpvote('r-1', true);

    expect(mockIO.to).toHaveBeenCalledWith('report:r-1');
    expect(mockIO.emit).toHaveBeenCalledWith('report:upvote', {
      report_id: 'r-1',
      upvoted: true,
    });
  });

  it('handles downvote (upvoted=false)', () => {
    broadcastUpvote('r-1', false);

    expect(mockIO.emit).toHaveBeenCalledWith('report:upvote', {
      report_id: 'r-1',
      upvoted: false,
    });
  });
});
