import { afterEach, describe, expect, it } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { BookingApp } from "./booking_app";

afterEach(cleanup);

const rooms = [
  {
    id: 1,
    name: "The Basement",
    description: "You walk down the stairs and your phone gives up.",
    capacity: 10,
    image_url: "/assets/house_of_horrors/room1.jpg"
  },
  {
    id: 2,
    name: "The Bathroom",
    description: "The mirror looks back and whispers: \"So... this is what we are wearing today?\" <script>alert(\"boo\")</script>",
    capacity: 1,
    image_url: "/assets/house_of_horrors/room2.jpg"
  }
];

describe("BookingApp", () => {
  it("shows the first room and switches the preview", () => {
    render(<BookingApp rooms={rooms} />);

    expect(screen.getByLabelText("Room")).toBeTruthy();
    expect(screen.getByRole("heading", { name: "The Basement" })).toBeTruthy();
    expect(screen.getByText(rooms[0].description)).toBeTruthy();
    expect(screen.getByText("Capacity: 10")).toBeTruthy();
    expect(screen.getByRole("img", { name: "The Basement" }).getAttribute("src")).toBe(rooms[0].image_url);

    fireEvent.change(screen.getByLabelText("Room"), { target: { value: "2" } });

    expect(screen.getByRole("heading", { name: "The Bathroom" })).toBeTruthy();
    expect(screen.getByText(rooms[1].description)).toBeTruthy();
    expect(screen.getByText("Capacity: 1")).toBeTruthy();
    expect(screen.getByRole("img", { name: "The Bathroom" }).getAttribute("src")).toBe(rooms[1].image_url);
    expect(document.querySelector("script")).toBeNull();
  });

  it("falls back to the first room when the selected room disappears", () => {
    const { rerender } = render(<BookingApp rooms={rooms} />);

    fireEvent.change(screen.getByLabelText("Room"), { target: { value: "2" } });
    rerender(<BookingApp rooms={[ rooms[0] ]} />);

    expect(screen.getByLabelText("Room").value).toBe("1");
    expect(screen.getByRole("heading", { name: "The Basement" })).toBeTruthy();
    expect(screen.getByText("Capacity: 10")).toBeTruthy();
  });

  it("shows a message when there are no rooms", () => {
    render(<BookingApp rooms={[]} />);

    expect(screen.getByText("No rooms are available right now.")).toBeTruthy();
    expect(screen.queryByLabelText("Room")).toBeNull();
  });
});
