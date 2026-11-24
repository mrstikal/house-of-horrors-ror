import { createRoot } from "react-dom/client";
import { BookingApp } from "./booking_app";

const root = document.getElementById("booking-root");

if (root) {
  const config = JSON.parse(root.dataset.config);
  createRoot(root).render(
    <BookingApp
      rooms={config.rooms}
      today={config.today}
      availabilityPath={config.availability_path}
      reservationsPath={config.reservations_path}
    />
  );
}
