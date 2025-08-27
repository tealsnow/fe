import {
  flexRender,
  getCoreRowModel,
  createSolidTable,
  Header,
  createColumnHelper,
  CellContext,
  RowData,
} from "@tanstack/solid-table";
import { createEffect, createMemo, createSignal, For } from "solid-js";
import { css } from "solid-styled-components";
import { cn } from "~/lib/cn";

type Person = {
  firstName: string;
  lastName: string;
  age: number;
  // visits: number;
  status: string;
  // progress: number;
};

const defaultData: Person[] = [
  {
    firstName: "tanner",
    lastName: "linsley",
    age: 24,
    // visits: 100,
    status: "In Relationship",
    // progress: 50,
  },
  {
    firstName: "tandy",
    lastName: "miller",
    age: 40,
    // visits: 40,
    status: "Single",
    // progress: 80,
  },
  {
    firstName: "joe",
    lastName: "dirte",
    age: 45,
    // visits: 20,
    status: "Complicated",
    // progress: 10,
  },
];

// const defaultColumns: ColumnDef<Person>[] = [
//   {
//     accessorKey: "firstName",
//     cell: (info) => info.getValue(),
//     // footer: (info) => info.column.id,
//     // footer: (info) => "asdf",
//   },
//   {
//     accessorFn: (row) => row.lastName,
//     id: "lastName",
//     cell: (info) => <i>{info.getValue<string>()}</i>,
//     header: () => <span>Last Name</span>,
//     // footer: (info) => info.column.id,
//   },
//   {
//     accessorKey: "age",
//     header: () => "Age",
//     // footer: (info) => info.column.id,
//   },
//   // {
//   //   accessorKey: "visits",
//   //   header: () => <span>Visits</span>,
//   //   // footer: (info) => info.column.id,
//   // },
//   {
//     accessorKey: "status",
//     header: "Status",
//     // footer: (info) => info.column.id,
//   },
//   // {
//   //   accessorKey: "progress",
//   //   header: "Profile Progress",
//   //   // footer: (info) => info.column.id,
//   // },
// ];

declare module "@tanstack/solid-table" {
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  interface TableMeta<TData extends RowData> {
    updateData: (rowIndex: number, columnId: string, value: unknown) => void;
  }

  // // eslint-disable-next-line @typescript-eslint/no-unused-vars
  // interface ColumnMeta<TData extends RowData, TValue> {
  //   mine?: string;
  // }
}

const EditCell = (props: CellContext<Person, string>) => {
  const [editing, setEditing] = createSignal(false);

  const initialValue = props.getValue();
  const [value, setValue] = createSignal(initialValue);

  // createEffect(() => {
  //   setValue(props.getValue());
  // });

  const update = () => {
    props.table.options.meta?.updateData(
      props.row.index,
      props.column.id,
      value(),
    );
  };

  let inputRef!: HTMLInputElement;
  createEffect(() => {
    if (editing()) {
      inputRef.focus();
      inputRef.select();
    } else {
      setValue(initialValue);
    }
  });

  return (
    <input
      ref={inputRef}
      type="text"
      class={cn(
        "w-full min-h-0 h-full p-0 px-1",
        "ring-0 bg-theme-background border border-theme-colors-blue-border",
        editing() &&
          "border-theme-colors-purple-border bg-theme-colors-purple-background",
      )}
      size={1}
      readOnly={!editing()}
      value={value()}
      onInput={(e) => setValue(e.target.value)}
      onDblClick={() => setEditing(true)}
      onBlur={() => setTimeout(() => setEditing(false), 100)}
      onKeyDown={({ key }) => {
        switch (key) {
          case "Enter":
            update();
            setEditing(false);
            break;
          case "Escape":
            setEditing(false);
            break;
        }
      }}
    />
  );
};

const columnHelper = createColumnHelper<Person>();

const defaultColumns = [
  columnHelper.accessor("firstName", {
    // cell: EditCell,
  }),
  columnHelper.accessor("lastName", {
    cell: EditCell,
  }),
  columnHelper.accessor("age", {
    // cell: EditCell,
  }),
  columnHelper.accessor("status", {
    // cell: EditCell,
  }),
];

export function App() {
  const [data, setData] = createSignal(defaultData);
  const rerender = () => setData(defaultData);

  const table = createSolidTable({
    get data() {
      return data();
    },
    columns: defaultColumns,
    // defaultColumn: {
    //   minSize: 60,
    //   maxSize: 800,
    // },
    enableColumnResizing: true,
    columnResizeMode: "onChange",
    getCoreRowModel: getCoreRowModel(),
    // debugTable: true,
    // debugHeaders: true,
    // debugColumns: true,

    meta: {
      updateData: (rowIndex: number, columnId: string, value: unknown) => {
        setData((old) =>
          old.map((row, index) => {
            if (index === rowIndex) {
              return {
                ...old[rowIndex],
                [columnId]: value,
              };
            }
            return row;
          }),
        );
      },
    },
  });

  const columnSizeVars = createMemo(() => {
    const headers = table.getFlatHeaders();
    const colSizes: { [key: string]: number } = {};

    for (let i = 0; i < headers.length; i++) {
      const header = headers[i]!;
      colSizes[`--header-${header.id}-size`] = header.getSize();
      colSizes[`--col-${header.column.id}-size`] = header.column.getSize();
    }
    return colSizes;
  });

  return (
    <div class={cn("p-2 text-sm/tight")}>
      {/*<pre>
        {JSON.stringify(
          { columnSizing: table.getState().columnSizing },
          null,
          2,
        )}
      </pre>*/}
      <div class="overflow-x-auto text-nowrap">
        <div // table
          class="border-t border-l border-b border-theme-border w-fit"
          style={{
            ...columnSizeVars(),
            width: `${table.getTotalSize()}`,
          }}
        >
          <div // thead
          >
            <For each={table.getHeaderGroups()}>
              {(headerGroup) => (
                <div // tr
                  class="flex w-fit"
                >
                  <For each={headerGroup.headers}>
                    {(header) => (
                      <div // th
                        class="p-1 relative font-bold text-center overflow-clip"
                        style={{
                          width: `calc(var(--header-${header?.id}-size) * 1px)`,
                        }}
                      >
                        {header.isPlaceholder
                          ? null
                          : flexRender(
                              header.column.columnDef.header,
                              header.getContext(),
                            )}
                        <ResizeHandle header={header} />
                      </div>
                    )}
                  </For>
                </div>
              )}
            </For>
          </div>
          <div // tbody
          >
            <For each={table.getRowModel().rows}>
              {(row) => (
                <div // tr
                  class="flex w-fit border-t border-theme-border"
                >
                  <For each={row.getVisibleCells()}>
                    {(cell) => (
                      <div // td
                        class="p-1 border-r border-theme-border overflow-clip"
                        style={{
                          width: `calc(var(--col-${cell.column.id}-size) * 1px)`,
                        }}
                      >
                        {/*{cell.renderValue<any>()}*/}
                        {flexRender(
                          cell.column.columnDef.cell,
                          cell.getContext(),
                        )}
                      </div>
                    )}
                  </For>
                </div>
              )}
            </For>
          </div>
        </div>
      </div>
      <div class="h-4" />
      <button onClick={() => rerender()} class="border p-2">
        Rerender
      </button>
      <pre>{JSON.stringify(data(), null, 2)}</pre>
    </div>
  );
}

type ResizeHandleProps = {
  header: Header<Person, unknown>;
};

const ResizeHandle = (props: ResizeHandleProps) => {
  return (
    <div
      onDblClick={() => props.header.column.resetSize()}
      onMouseDown={props.header.getResizeHandler()}
      onTouchStart={props.header.getResizeHandler()}
      class={cn(
        "absolute top-0 h-full right-0 w-[1px] bg-theme-border cursor-col-resize select-none touch-none",
        props.header.column.getIsResizing() && "bg-theme-text",
        css`
          &::before {
            content: "";
            top: 0;
            position: absolute;
            height: 100%;
            width: 1rem;
            left: -0.5rem;
            cursor: ew-resize;
          }
        `,
      )}
    />
  );
};

export default App;
