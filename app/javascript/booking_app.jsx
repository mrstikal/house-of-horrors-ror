import { useEffect, useRef, useState } from "react";

async function readErrorMessage(response) {
  try {
    const payload = await response.json();
    const messages = payload?.error?.messages;

    return Array.isArray(messages) && messages.length > 0 ? messages.join(" ") : null;
  } catch {
    return null;
  }
}

export function BookingApp({
  rooms = [],
  today = "",
  availabilityPath,
  reservationsPath
}) {
  const [selectedRoomId, setSelectedRoomId] = useState(rooms[0]?.id ?? null);
  const [date, setDate] = useState(today);
  const [selectedHour, setSelectedHour] = useState("");
  const [slots, setSlots] = useState([]);
  const [status, setStatus] = useState("loading");
  const [submitting, setSubmitting] = useState(false);
  const [feedback, setFeedback] = useState(null);
  const [refreshKey, setRefreshKey] = useState(0);
  const generationRef = useRef(0);
  const submittingRef = useRef(false);

  const effectiveRoomId = rooms.some((room) => room.id === selectedRoomId)
    ? selectedRoomId
    : rooms[0]?.id ?? null;
  const selectedRoom = rooms.find((room) => room.id === effectiveRoomId);
  const selectedSlot = slots.find((slot) => String(slot.start_hour) === selectedHour);
  const hasInputs = Boolean(effectiveRoomId && date);
  const canSubmit = Boolean(
    selectedHour &&
    selectedSlot &&
    reservationsPath &&
    status !== "loading" &&
    !submitting
  );

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
  }, [effectiveRoomId, date, availabilityPath, refreshKey]);

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
    setFeedback(null);
  };

  const handleDateChange = (event) => {
    generationRef.current += 1;
    setDate(event.target.value);
    setSelectedHour("");
    setSlots([]);
    setStatus("loading");
    setFeedback(null);
  };

  const submitBooking = async () => {
    if (!canSubmit || submittingRef.current) return;

    submittingRef.current = true;
    const requestedRoomId = effectiveRoomId;
    const requestedDate = date;
    const requestedHour = Number(selectedHour);
    const token = document.querySelector("meta[name='csrf-token']")?.content;

    setSubmitting(true);
    setFeedback(null);

    try {
      const response = await fetch(reservationsPath, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          ...(token ? { "X-CSRF-Token": token } : {})
        },
        credentials: "same-origin",
        body: JSON.stringify({
          reservation: {
            room_id: requestedRoomId,
            date: requestedDate,
            start_hour: requestedHour
          }
        })
      });

      if (response.ok) {
        setFeedback({ kind: "success", message: "Your booking is confirmed." });
      } else {
        const message = await readErrorMessage(response);

        if (response.status === 409) {
          setFeedback({
            kind: "error",
            message: message || "This slot has just filled up. Select another time."
          });
        } else {
          setFeedback({
            kind: "error",
            message: message || "The booking could not be completed. Try again."
          });
        }
      }
    } catch {
      setFeedback({
        kind: "error",
        message: "The booking could have succeeded, but the connection failed. Refreshing availability does not confirm its outcome."
      });
    } finally {
      submittingRef.current = false;
      setSelectedHour("");
      setSubmitting(false);
      setRefreshKey((value) => value + 1);
    }
  };

  return (
    <section className="booking" aria-labelledby="booking-heading">
      <h2 id="booking-heading">Book a room</h2>
      <div className="booking-controls">
        <label htmlFor="room-select">Room</label>
        <select
          id="room-select"
          value={effectiveRoomId}
          onChange={handleRoomChange}
          disabled={submitting}
        >
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
          disabled={submitting}
        />

        <label htmlFor="slot-select">Start time</label>
        <select
          id="slot-select"
          value={selectedHour}
          onChange={(event) => setSelectedHour(event.target.value)}
          disabled={submitting}
        >
          <option value="">Select a time</option>
          {slots.map((slot) => (
            <option key={slot.start_hour} value={slot.start_hour}>
              {slot.label} ({slot.remaining} {slot.remaining === 1 ? "place" : "places"} left)
            </option>
          ))}
        </select>
      </div>

      <div className="booking-actions">
        <button
          type="button"
          className="booking-submit"
          onClick={submitBooking}
          disabled={!canSubmit}
        >
          {submitting ? "Booking…" : "Book this slot"}
        </button>
      </div>

      {feedback && (
        <p
          className={feedback.kind === "success" ? "booking-success" : "booking-feedback-error"}
          role={feedback.kind === "success" ? "status" : "alert"}
        >
          {feedback.message}
        </p>
      )}

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
