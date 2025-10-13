/* @refresh reload */
import { render } from "solid-js/web";

import App from "~/App";
import "~/index.css";

document.title = "Fe";

const dispose = render(
  () => <App />,
  document.getElementById("root") as HTMLElement,
);
if (import.meta.hot) import.meta.hot.dispose(dispose);
