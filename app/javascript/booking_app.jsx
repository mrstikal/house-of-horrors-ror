import { useEffect, useRef, useState } from "react";

export function BookingApp({ rooms = [], today = "", availabilityPath }) {
  const [selectedRoomId, setSelectedRoomId] = useState(rooms[0]?.id ?? null);
  const [date, setDate] = useState(today);
  const [selectedHour, setSelectedHour] = useState("");
  const [slots, setSlots] = useState([]);
  const [status, setStatus] = useState("loading");
  const generationRef = useRef(0);

  const effectiveRoomId = rooms.some((room) => room.id === selectedRoomId)
    ? selectedRoomId
    : rooms[0]?.id ?? null;
  const selectedRoom = rooms.find((room) => room.id === effectiveRoomId);
  const selectedSlot = slots.find((slot) => String(slot.start_hour) === selectedHour);
  const hasInputs = Boolean(effectiveRoomId && date);

  useEffect(() => {
    if (!effectiveRoomId || !date || !availabilityPath) {
      generationRef.current += 1;
      setSlots([]);
      setSelectedHour("");
      setStatus("idle");
      return undefined;
    }

    const controller = new AbortController();
    const generation = generationRef.current + 1;
    generationRef.current = generation;
    const requestedRoomId = effectiveRoomId;
    const requestedDate = date;
    let cancelled = false;
    const params = new URLSearchParams({
      room_id: String(requestedRoomId),
      date: requestedDate
    });

    setSlots([]);
    setSelectedHour("");
    setStatus("loading");

    fetch(`${availabilityPath}?${params.toString()}`, {
      headers: { Accept: "application/json" },
      credentials: "same-origin",
      signal: controller.signal
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error(`Availability request failed with ${response.status}`);
        }
        return response.json();
      })
      .then((payload) => {
        if (cancelled || generation !== generationRef.current) return;

        if (String(payload.room_id) !== String(requestedRoomId) || payload.date !== requestedDate) {
          setSlots([]);
          setStatus("error");
          return;
        }

        setSlots(Array.isArray(payload.slots) ? payload.slots : []);
        setStatus("idle");
      })
      .catch((error) => {
        if (cancelled || generation !== generationRef.current) return;
        if (error.name === "AbortError") return;

        setSlots([]);
        setStatus("error");
      });

    return () => {
      cancelled = true;
      controller.abort();
    };
  }, [effectiveRoomId, date, availabilityPath]);

  if (rooms.length === 0) {
    return (
      <section className="booking" aria-labelledby="booking-heading">
        <h2 id="booking-heading">Book a room</h2>
        <p>No rooms are available right now.</p>
      </section>
    );
  }

  const handleRoomChange = (event) => {
    generationRef.current += 1;
    setSelectedRoomId(Number(event.target.value));
    setSelectedHour("");
    setSlots([]);
    setStatus("loading");
  };

  const handleDateChange = (event) => {
    generationRef.current += 1;
    setDate(event.target.value);
    setSelectedHour("");
    setSlots([]);
    setStatus("loading");
  };

  return (
    <section className="booking" aria-labelledby="booking-heading">
      <h2 id="booking-heading">Book a room</h2>
      <div className="booking-controls">
        <label htmlFor="room-select">Room</label>
        <select id="room-select" value={effectiveRoomId} onChange={handleRoomChange}>
          {rooms.map((room) => (
            <option key={room.id} value={room.id}>
              {room.name}
            </option>
          ))}
        </select>

        <label htmlFor="date-input">Date</label>
        <input
          id="date-input"
          type="date"
          value={date}
          min={today || undefined}
          onChange={handleDateChange}
        />

        <label htmlFor="slot-select">Start time</label>
        <select
          id="slot-select"
          value={selectedHour}
          onChange={(event) => setSelectedHour(event.target.value)}
        >
          <option value="">Select a time</option>
          {slots.map((slot) => (
            <option key={slot.start_hour} value={slot.start_hour}>
              {slot.label} ({slot.remaining} {slot.remaining === 1 ? "place" : "places"} left)
            </option>
          ))}
        </select>
      </div>

      {!hasInputs && (
        <p className="booking-status" role="status">Select a room and date to see available times.</p>
      )}
      {hasInputs && status === "loading" && (
        <p className="booking-status" role="status">Loading available slots…</p>
      )}
      {hasInputs && status === "error" && (
        <p className="booking-error" role="alert">Availability could not be loaded. Try again.</p>
      )}
      {hasInputs && status === "idle" && slots.length === 0 && (
        <p className="booking-status" role="status">No available slots for this room and date.</p>
      )}
      {selectedSlot?.nearly_full && (
        <p className="slot-warning" role="status">Only 1 place left!</p>
      )}

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
