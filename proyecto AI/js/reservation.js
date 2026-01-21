const form = document.getElementById("reservationForm");
const successBox = document.getElementById("successBox");

const nameInput = document.getElementById("name");
const peopleInput = document.getElementById("people");
const phoneInput = document.getElementById("phone");
const dateInput = document.getElementById("date");
const timeSelect = document.getElementById("time");

const errName = document.getElementById("err-name");
const errPeople = document.getElementById("err-people");
const errPhone = document.getElementById("err-phone");
const errDate = document.getElementById("err-date");
const errTime = document.getElementById("err-time");

// DATE & TIME
function updateDateTime() {
    const el = document.getElementById("datetime");
    el.textContent = new Date().toLocaleString();
}
setInterval(updateDateTime, 1000);
updateDateTime();

// TIME OPTIONS
for (let h = 12; h <= 23; h++) {
    timeSelect.innerHTML += `<option value="${h}:00">${h}:00</option>`;
}

// VALIDATION
function clearErrors() {
    errName.textContent = "";
    errPeople.textContent = "";
    errPhone.textContent = "";
    errDate.textContent = "";
    errTime.textContent = "";
}

form.addEventListener("submit", (e) => {
    e.preventDefault();
    clearErrors();

    let ok = true;

    if (!nameInput.value.trim()) {
        errName.textContent = "Name is required";
        ok = false;
    }

    if (peopleInput.value < 1) {
        errPeople.textContent = "At least 1 person";
        ok = false;
    }

    if (!phoneInput.value.trim()) {
        errPhone.textContent = "Phone is required";
        ok = false;
    }

    if (!dateInput.value) {
        errDate.textContent = "Date is required";
        ok = false;
    }

    if (!timeSelect.value) {
        errTime.textContent = "Time is required";
        ok = false;
    }

    if (!ok) return;

    successBox.style.display = "block";
    successBox.textContent = "Reservation confirmed!";
});
