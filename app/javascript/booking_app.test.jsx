import { afterEach, describe, expect, it, vi } from "vitest";
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within
} from "@testing-library/react";
import { BookingApp } from "./booking_app";

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  document.querySelectorAll("meta[name='csrf-token']").forEach((meta) => meta.remove());
});

const TODAY = "2026-11-24";
const AVAILABILITY_PATH = "/api/availability";
const RESERVATIONS_PATH = "/api/reservations";

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

function slot(hour, remaining, nearlyFull = false) {
  const start = String(hour).padStart(2, "0");
  const finish = String(hour + 1).padStart(2, "0");

  return {
    start_hour: hour,
    start_datetime: `2026-11-24T${start}:00:00Z`,
    end_datetime: `2026-11-24T${finish}:00:00Z`,
    label: `${start}:00-${finish}:00 UTC`,
    remaining,
    nearly_full: nearlyFull
  };
}

function jsonResponse(payload) {
  return { ok: true, json: async () => payload };
}

function availability(roomId, date, slots) {
  return jsonResponse({ room_id: roomId, date, slots });
}

function deferred() {
  let resolve;
  const promise = new Promise((resolver) => {
    resolve = resolver;
  });

  return { promise, resolve };
}

function setCsrfToken(token = "test-csrf-token") {
  const meta = document.createElement("meta");
  meta.setAttribute("name", "csrf-token");
  meta.setAttribute("content", token);
  document.head.appendChild(meta);
}

function renderApp(fetchMock, props = {}) {
  vi.stubGlobal("fetch", fetchMock);

  return render(
    <BookingApp
      rooms={rooms}
      today={TODAY}
      availabilityPath={AVAILABILITY_PATH}
      reservationsPath={RESERVATIONS_PATH}
      {...props}
    />
  );
}

describe("BookingApp", () => {
  it("shows the first room and switches the preview", () => {
    const fetchMock = vi.fn();
    renderApp(fetchMock, { today: "" });

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
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("falls back to the first room when the selected room disappears", () => {
    const fetchMock = vi.fn();
    const { rerender } = renderApp(fetchMock, { today: "" });

    fireEvent.change(screen.getByLabelText("Room"), { target: { value: "2" } });
    rerender(
      <BookingApp
        rooms={[ rooms[0] ]}
        today=""
        availabilityPath={AVAILABILITY_PATH}
      />
    );

    expect(screen.getByLabelText("Room").value).toBe("1");
    expect(screen.getByRole("heading", { name: "The Basement" })).toBeTruthy();
    expect(screen.getByText("Capacity: 10")).toBeTruthy();
  });

  it("shows a message when there are no rooms", () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    render(<BookingApp rooms={[]} today={TODAY} availabilityPath={AVAILABILITY_PATH} />);

    expect(screen.getByText("No rooms are available right now.")).toBeTruthy();
    expect(screen.queryByLabelText("Room")).toBeNull();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("fetches the first room for server today and leaves the slot unselected", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      availability(1, TODAY, [ slot(1, 2), slot(2, 1, true) ])
    );
    renderApp(fetchMock);

    expect(screen.getByLabelText("Date (UTC)").value).toBe(TODAY);
    expect(screen.getByLabelText("Date (UTC)").min).toBe(TODAY);
    expect(screen.getByLabelText("Start time").value).toBe("");

    const option = await screen.findByRole("option", { name: /01:00-02:00 UTC/ });

    expect(option.textContent).toContain("2 places left");
    expect(screen.getByLabelText("Start time").value).toBe("");
    expect(screen.queryByText("Only 1 place left!")).toBeNull();
    expect(screen.getByRole("button", { name: "Book this slot" }).disabled).toBe(true);

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [ url, options ] = fetchMock.mock.calls[0];
    expect(url).toBe(`${AVAILABILITY_PATH}?room_id=1&date=${TODAY}`);
    expect(options.credentials).toBe("same-origin");
    expect(options.headers).toEqual({ Accept: "application/json" });
  });

  it("shows the warning only for a selected nearly-full slot", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      availability(1, TODAY, [ slot(1, 1, true), slot(2, 1, false) ])
    );
    renderApp(fetchMock);

    const slotSelect = await screen.findByLabelText("Start time");
    await waitFor(() => expect(within(slotSelect).getByRole("option", { name: /01:00-02:00 UTC/ })).toBeTruthy());

    fireEvent.change(slotSelect, { target: { value: "1" } });
    expect(screen.getByText("Only 1 place left!")).toBeTruthy();

    const singlePlace = within(slotSelect).getByRole("option", { name: /01:00-02:00 UTC/ });
    expect(singlePlace.textContent).toContain("1 place left");
    expect(singlePlace.textContent).not.toContain("1 places left");

    fireEvent.change(slotSelect, { target: { value: "2" } });
    expect(screen.queryByText("Only 1 place left!")).toBeNull();
  });

  it("rejects a current payload whose room or date does not match the request", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      availability(999, TODAY, [ slot(1, 2) ])
    );
    renderApp(fetchMock);

    expect((await screen.findByRole("alert")).textContent).toBe("Availability could not be loaded. Try again.");
    expect(screen.queryByRole("option", { name: /01:00-02:00 UTC/ })).toBeNull();
    expect(screen.getByLabelText("Start time").value).toBe("");
  });

  it("clears the selection and old slots when room or date changes", async () => {
    const fetchMock = vi.fn((url) => {
      const parsed = new URL(url, "http://localhost");
      const roomId = Number(parsed.searchParams.get("room_id"));
      const date = parsed.searchParams.get("date");

      return Promise.resolve(availability(roomId, date, [ slot(roomId === 1 ? 1 : 2, 2) ]));
    });
    renderApp(fetchMock);

    const slotSelect = await screen.findByLabelText("Start time");
    await waitFor(() => expect(within(slotSelect).getByRole("option", { name: /01:00-02:00 UTC/ })).toBeTruthy());
    fireEvent.change(slotSelect, { target: { value: "1" } });
    expect(slotSelect.value).toBe("1");

    fireEvent.change(screen.getByLabelText("Room"), { target: { value: "2" } });

    expect(screen.getByLabelText("Start time").value).toBe("");
    expect(within(screen.getByLabelText("Start time")).queryByRole("option", { name: /01:00-02:00 UTC/ })).toBeNull();
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
    expect(fetchMock.mock.calls[1][0]).toBe(`${AVAILABILITY_PATH}?room_id=2&date=${TODAY}`);

    fireEvent.change(screen.getByLabelText("Date (UTC)"), { target: { value: "2026-11-25" } });

    expect(screen.getByLabelText("Start time").value).toBe("");
    expect(within(screen.getByLabelText("Start time")).queryByRole("option", { name: /02:00-03:00 UTC/ })).toBeNull();
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(3));
    expect(fetchMock.mock.calls[2][0]).toBe(`${AVAILABILITY_PATH}?room_id=2&date=2026-11-25`);
  });

  it("ignores a late response from a superseded request", async () => {
    const first = deferred();
    const second = deferred();
    const fetchMock = vi.fn()
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise);
    renderApp(fetchMock);

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    const firstSignal = fetchMock.mock.calls[0][1].signal;

    fireEvent.change(screen.getByLabelText("Room"), { target: { value: "2" } });
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
    expect(firstSignal.aborted).toBe(true);

    await act(async () => {
      second.resolve(availability(2, TODAY, [ slot(2, 4) ]));
      await Promise.resolve();
    });
    expect(await screen.findByRole("option", { name: /02:00-03:00 UTC/ })).toBeTruthy();

    await act(async () => {
      first.resolve(availability(1, TODAY, [ slot(1, 9) ]));
      await Promise.resolve();
    });

    expect(screen.queryByRole("option", { name: /01:00-02:00 UTC/ })).toBeNull();
    expect(screen.getByRole("option", { name: /02:00-03:00 UTC/ })).toBeTruthy();
  });

  it("shows loading, empty and error states without stale options", async () => {
    const pending = deferred();
    const fetchMock = vi.fn()
      .mockReturnValueOnce(pending.promise)
      .mockRejectedValueOnce(new Error("network"));
    renderApp(fetchMock);

    expect(screen.getByText("Loading available slots…")).toBeTruthy();

    await act(async () => {
      pending.resolve(availability(1, TODAY, []));
      await Promise.resolve();
    });
    expect(await screen.findByText("No available slots for this room and date.")).toBeTruthy();
    expect(screen.getByLabelText("Start time").value).toBe("");
    expect(within(screen.getByLabelText("Start time")).queryAllByRole("option")).toHaveLength(1);

    fireEvent.change(screen.getByLabelText("Date (UTC)"), { target: { value: "2026-11-25" } });

    expect((await screen.findByRole("alert")).textContent).toBe("Availability could not be loaded. Try again.");
    expect(screen.getByLabelText("Start time").value).toBe("");
    expect(within(screen.getByLabelText("Start time")).queryAllByRole("option")).toHaveLength(1);
  });

  it("shows the server reason for an availability failure and retries the same request", async () => {
    const failure = {
      ok: false,
      status: 503,
      json: async () => ({
        error: {
          code: "busy",
          messages: [ "The booking system is busy. Try again." ]
        }
      })
    };
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(failure)
      .mockResolvedValueOnce(availability(1, TODAY, [ slot(1, 2) ]));
    renderApp(fetchMock);

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toBe("The booking system is busy. Try again.");

    fireEvent.click(screen.getByRole("button", { name: "Try again" }));

    expect(await screen.findByRole("option", { name: /01:00-02:00 UTC/ })).toBeTruthy();
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[1][0]).toBe(`${AVAILABILITY_PATH}?room_id=1&date=${TODAY}`);
    expect(screen.queryByRole("alert")).toBeNull();
  });

  it("keeps large room ids as exact strings in requests", async () => {
    const largeId = "9007199254740993";
    const fetchMock = vi.fn().mockResolvedValue(availability(largeId, TODAY, [ slot(1, 2) ]));
    vi.stubGlobal("fetch", fetchMock);

    render(
      <BookingApp
        rooms={[ { ...rooms[0], id: largeId } ]}
        today={TODAY}
        availabilityPath={AVAILABILITY_PATH}
        reservationsPath={RESERVATIONS_PATH}
      />
    );

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    expect(fetchMock.mock.calls[0][0]).toBe(
      `${AVAILABILITY_PATH}?room_id=${largeId}&date=${TODAY}`
    );
  });

  it("does not fetch until both room and date are present", async () => {
    const fetchMock = vi.fn().mockResolvedValue(availability(1, TODAY, []));
    renderApp(fetchMock, { today: "" });

    expect(screen.getByText("Select a room and date to see available times.")).toBeTruthy();
    expect(fetchMock).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("Date (UTC)"), { target: { value: TODAY } });

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    expect(fetchMock.mock.calls[0][0]).toBe(`${AVAILABILITY_PATH}?room_id=1&date=${TODAY}`);
  });

  it("keeps submission disabled until a currently offered hour is selected", async () => {
    const fetchMock = vi.fn().mockResolvedValue(availability(1, TODAY, [ slot(1, 2) ]));
    renderApp(fetchMock);

    const submit = screen.getByRole("button", { name: "Book this slot" });
    expect(submit.disabled).toBe(true);

    const slotSelect = await screen.findByLabelText("Start time");
    await waitFor(() => expect(within(slotSelect).getByRole("option", { name: /01:00-02:00 UTC/ })).toBeTruthy());
    expect(submit.disabled).toBe(true);

    fireEvent.change(slotSelect, { target: { value: "1" } });
    expect(submit.disabled).toBe(false);
  });

  it("posts once with the CSRF token and body, then refreshes without clearing feedback", async () => {
    setCsrfToken();
    const refresh = deferred();
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(availability(1, TODAY, [ slot(1, 1, true) ]))
      .mockResolvedValueOnce(jsonResponse({ reservation: { id: 12 } }))
      .mockReturnValueOnce(refresh.promise);
    renderApp(fetchMock);

    const slotSelect = await screen.findByLabelText("Start time");
    await waitFor(() => expect(within(slotSelect).getByRole("option", { name: /01:00-02:00 UTC/ })).toBeTruthy());
    fireEvent.change(slotSelect, { target: { value: "1" } });
    fireEvent.click(screen.getByRole("button", { name: "Book this slot" }));

    expect(await screen.findByText("Your booking is confirmed.")).toBeTruthy();
    await waitFor(() => {
      expect(document.activeElement).toBe(screen.getByText("Your booking is confirmed."));
    });

    const posts = fetchMock.mock.calls.filter(([, options]) => options?.method === "POST");
    expect(posts).toHaveLength(1);
    const [ url, options ] = posts[0];
    expect(url).toBe(RESERVATIONS_PATH);
    expect(options.credentials).toBe("same-origin");
    expect(options.headers).toEqual({
      Accept: "application/json",
      "Content-Type": "application/json",
      "X-CSRF-Token": "test-csrf-token"
    });
    expect(JSON.parse(options.body)).toEqual({
      reservation: { room_id: "1", date: TODAY, start_hour: 1 }
    });

    expect(screen.getByLabelText("Start time").value).toBe("");
    await waitFor(() => {
      expect(fetchMock.mock.calls.filter(([ requestUrl ]) => requestUrl.startsWith(AVAILABILITY_PATH))).toHaveLength(2);
    });
    expect(fetchMock.mock.calls.at(-1)[0]).toBe(`${AVAILABILITY_PATH}?room_id=1&date=${TODAY}`);

    fireEvent.click(screen.getByRole("button", { name: "Book this slot" }));
    expect(fetchMock.mock.calls.filter(([, options]) => options?.method === "POST")).toHaveLength(1);
    expect(screen.getByText("Your booking is confirmed.")).toBeTruthy();

    await act(async () => {
      refresh.resolve(availability(1, TODAY, []));
      await Promise.resolve();
    });

    expect(screen.getByText("Your booking is confirmed.")).toBeTruthy();
  });

  it("shows conflict feedback and refreshes after a 409 without clearing it", async () => {
    setCsrfToken();
    const refresh = deferred();
    const conflict = {
      ok: false,
      status: 409,
      json: async () => ({
        error: {
          code: "slot_full",
          messages: [ "This slot has just filled up. Select another time." ]
        }
      })
    };
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(availability(1, TODAY, [ slot(1, 1, true) ]))
      .mockResolvedValueOnce(conflict)
      .mockReturnValueOnce(refresh.promise);
    renderApp(fetchMock);

    const slotSelect = await screen.findByLabelText("Start time");
    await waitFor(() => expect(within(slotSelect).getByRole("option", { name: /01:00-02:00 UTC/ })).toBeTruthy());
    fireEvent.change(slotSelect, { target: { value: "1" } });
    fireEvent.click(screen.getByRole("button", { name: "Book this slot" }));

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toBe("This slot has just filled up. Select another time.");
    expect(screen.getByLabelText("Start time").value).toBe("");

    await waitFor(() => {
      expect(fetchMock.mock.calls.filter(([ requestUrl ]) => requestUrl.startsWith(AVAILABILITY_PATH))).toHaveLength(2);
    });
    expect(screen.getByRole("alert").textContent).toBe("This slot has just filled up. Select another time.");

    await act(async () => {
      refresh.resolve(availability(1, TODAY, []));
      await Promise.resolve();
    });

    expect(screen.getByRole("alert").textContent).toBe("This slot has just filled up. Select another time.");
  });

  it("reports an ambiguous network failure and refreshes without auto-posting", async () => {
    setCsrfToken();
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(availability(1, TODAY, [ slot(1, 1, true) ]))
      .mockRejectedValueOnce(new TypeError("Failed to fetch"))
      .mockResolvedValueOnce(availability(1, TODAY, []));
    renderApp(fetchMock);

    const slotSelect = await screen.findByLabelText("Start time");
    await waitFor(() => expect(within(slotSelect).getByRole("option", { name: /01:00-02:00 UTC/ })).toBeTruthy());
    fireEvent.change(slotSelect, { target: { value: "1" } });
    fireEvent.click(screen.getByRole("button", { name: "Book this slot" }));

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toContain("could have succeeded");
    expect(alert.textContent).toContain("does not confirm");

    await waitFor(() => {
      expect(fetchMock.mock.calls.filter(([ requestUrl ]) => requestUrl.startsWith(AVAILABILITY_PATH))).toHaveLength(2);
    });
    const posts = fetchMock.mock.calls.filter(([, options]) => options?.method === "POST");
    expect(posts).toHaveLength(1);
    expect(screen.getByRole("alert").textContent).toContain("could have succeeded");
  });

  it("disables edits and submission while a POST is pending", async () => {
    setCsrfToken();
    const post = deferred();
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(availability(1, TODAY, [ slot(1, 1, true) ]))
      .mockReturnValueOnce(post.promise)
      .mockResolvedValueOnce(availability(1, TODAY, []));
    renderApp(fetchMock);

    const slotSelect = await screen.findByLabelText("Start time");
    await waitFor(() => expect(within(slotSelect).getByRole("option", { name: /01:00-02:00 UTC/ })).toBeTruthy());
    fireEvent.change(slotSelect, { target: { value: "1" } });
    fireEvent.click(screen.getByRole("button", { name: "Book this slot" }));

    expect(screen.getByLabelText("Room").disabled).toBe(true);
    expect(screen.getByLabelText("Date (UTC)").disabled).toBe(true);
    expect(screen.getByLabelText("Start time").disabled).toBe(true);
    const booking = screen.getByRole("button", { name: "Booking…" });
    expect(booking.disabled).toBe(true);
    fireEvent.click(booking);
    expect(fetchMock.mock.calls.filter(([, options]) => options?.method === "POST")).toHaveLength(1);

    await act(async () => {
      post.resolve(jsonResponse({ reservation: { id: 13 } }));
      await Promise.resolve();
    });

    await waitFor(() => expect(screen.getByLabelText("Room").disabled).toBe(false));
    expect(screen.getByLabelText("Date (UTC)").disabled).toBe(false);
  });
});
