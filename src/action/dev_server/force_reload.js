const reconnect = () => {
  fetch(window.location.href, { mode: "no-cors" })
    .then((result) => {
      if (result.status != 200) {
        console.clear();
        console.log("Reconnecting ...");
        setTimeout(reconnect, 500);
      } else {
        setTimeout(connect, 500);
      }
    })
    .catch(() => {
      console.clear();
      console.log("Reconnecting ...");
      setTimeout(reconnect, 500);
    });
};

const connect = () => {
  let socket = new WebSocket("ws://localhost:1331/ws");
  let timestamp;
  let dead = false;

  socket.onopen = () => {
    if (dead) return;
    console.log("Socket open");
    timestamp = new Date().getTime();
  };

  socket.onmessage = (e) => {
    if (dead) return;
    switch (e.data) {
      case "reload":
        console.log("Reload recieved");
        socket.send(JSON.stringify("reloading"));
        dead = true;
        window.location.reload();
        break;
      case "connect":
        console.log("Connected to server");
        break;
      default:
        console.log("Unknown message: ", e.data);
    }
  };

  socket.onclose = () => {
    if (dead) return;
    console.log("Socket closed");
    setTimeout(reconnect, 500);
  };

  socket.onerror = (e) => {
    if (dead) return;
    console.log("Error: ", e);
    socket.close();
    dead = true;
    setTimeout(reconnect, 500);
  };
};

connect();
