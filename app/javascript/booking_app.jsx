import { useState } from "react";

export function BookingApp({ rooms = [] }) {
  const [selectedRoomId, setSelectedRoomId] = useState(rooms[0]?.id ?? null);
  const effectiveRoomId = rooms.some((room) => room.id === selectedRoomId)
    ? selectedRoomId
    : rooms[0]?.id ?? null;
  const selectedRoom = rooms.find((room) => room.id === effectiveRoomId);

  if (rooms.length === 0) {
    return (
      <section className="booking" aria-labelledby="booking-heading">
        <h2 id="booking-heading">Book a room</h2>
        <p>No rooms are available right now.</p>
      </section>
    );
  }

  return (
    <section className="booking" aria-labelledby="booking-heading">
      <h2 id="booking-heading">Book a room</h2>
      <div className="booking-controls">
        <label htmlFor="room-select">Room</label>
        <select
          id="room-select"
          value={effectiveRoomId}
          onChange={(event) => setSelectedRoomId(Number(event.target.value))}
        >
          {rooms.map((room) => (
            <option key={room.id} value={room.id}>
              {room.name}
            </option>
          ))}
        </select>
      </div>
      {selectedRoom && (
        <article className="room-preview" aria-labelledby="room-preview-name">
          <img src={selectedRoom.image_url} alt={selectedRoom.name} />
          <div>
            <h3 id="room-preview-name">{selectedRoom.name}</h3>
            <p>{selectedRoom.description}</p>
            <p>Capacity: {selectedRoom.capacity}</p>
          </div>
        </article>
      )}
    </section>
  );
}
