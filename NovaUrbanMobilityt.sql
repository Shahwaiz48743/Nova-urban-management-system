-- Create a fresh, clearly named database for an urban micro-mobility + drone delivery platform
CREATE DATABASE NovaUrbanMobilityDB;
GO

-- Switch context to the new database so all objects land in the right place
USE NovaUrbanMobilityDB;
GO

/* =========================
   CORE: shared reference data
   ========================= */

-- Cities let us scope operations and pricing by municipality
CREATE TABLE Cities (
    CityId           INT IDENTITY(1,1) PRIMARY KEY,
    Name             NVARCHAR(120)      NOT NULL,
    CountryCode      CHAR(2)            NOT NULL,
    TimezoneIana     NVARCHAR(60)       NOT NULL,
    IsActive         BIT                NOT NULL CONSTRAINT DF_Cities_IsActive DEFAULT(1),
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Cities_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_Cities UNIQUE (Name, CountryCode)
);

-- Zones define geofenced areas inside a city (useful for routing and pricing)
CREATE TABLE Zones (
    ZoneId           INT IDENTITY(1,1) PRIMARY KEY,
    CityId           INT                NOT NULL,
    Code             NVARCHAR(50)       NOT NULL,
    Name             NVARCHAR(150)      NOT NULL,
    PolygonWkt       NVARCHAR(MAX)      NOT NULL, -- WKT polygon to keep GIS simple
    IsRestricted     BIT                NOT NULL CONSTRAINT DF_Zones_IsRestricted DEFAULT(0),
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Zones_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_Zones UNIQUE (CityId, Code),
    CONSTRAINT FK_Zones_Cities FOREIGN KEY (CityId) REFERENCES Cities(CityId)
);

-- Addresses capture geo + human-friendly labels for pickups and deliveries
CREATE TABLE Addresses (
    AddressId        BIGINT IDENTITY(1,1) PRIMARY KEY,
    CityId           INT                NOT NULL,
    Line1            NVARCHAR(200)      NOT NULL,
    Line2            NVARCHAR(200)      NULL,
    PostalCode       NVARCHAR(20)       NULL,
    Latitude         DECIMAL(9,6)       NULL,
    Longitude        DECIMAL(9,6)       NULL,
    PlaceLabel       NVARCHAR(120)      NULL,
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Addresses_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT FK_Addresses_Cities FOREIGN KEY (CityId) REFERENCES Cities(CityId)
);

-- Organizations represent merchants, partners, or internal units
CREATE TABLE Organizations (
    OrganizationId   INT IDENTITY(1,1) PRIMARY KEY,
    Name             NVARCHAR(160)      NOT NULL,
    Type             NVARCHAR(40)       NOT NULL,  -- 'Merchant','Partner','Internal'
    IsActive         BIT                NOT NULL CONSTRAINT DF_Orgs_IsActive DEFAULT(1),
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Orgs_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT CK_Organizations_Type CHECK (Type IN (N'Merchant', N'Partner', N'Internal')),
    CONSTRAINT UQ_Organizations_Name UNIQUE (Name)
);

-- People table centralizes identity for couriers, customers, and contacts
CREATE TABLE Persons (
    PersonId         BIGINT IDENTITY(1,1) PRIMARY KEY,
    FirstName        NVARCHAR(80)       NOT NULL,
    LastName         NVARCHAR(80)       NOT NULL,
    Email            NVARCHAR(200)      NULL,
    Phone            NVARCHAR(40)       NULL,
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Persons_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_Persons_Email UNIQUE (Email)
);

/* =========================
   SECURITY: users and access
   ========================= */

-- Users map authentication to a person with status flags for compliance
CREATE TABLE Users (
    UserId           INT IDENTITY(1,1) PRIMARY KEY,
    PersonId         BIGINT             NOT NULL,
    Username         NVARCHAR(120)      NOT NULL,
    PasswordHash     VARBINARY(256)     NOT NULL,
    IsLocked         BIT                NOT NULL CONSTRAINT DF_Users_IsLocked DEFAULT(0),
    LastLoginAt      DATETIME2(3)       NULL,
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_Users_Username UNIQUE (Username),
    CONSTRAINT FK_Users_Persons FOREIGN KEY (PersonId) REFERENCES Persons(PersonId)
);

-- Roles keep authorization simple and auditable
CREATE TABLE Roles (
    RoleId           INT IDENTITY(1,1) PRIMARY KEY,
    Name             NVARCHAR(80)       NOT NULL,
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Roles_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_Roles_Name UNIQUE (Name)
);

-- User-to-role mapping enables many-to-many permissioning
CREATE TABLE UserRoles (
    UserId           INT NOT NULL,
    RoleId           INT NOT NULL,
    AssignedAt       DATETIME2(3) NOT NULL CONSTRAINT DF_UserRoles_AssignedAt DEFAULT(SYSDATETIME()),
    PRIMARY KEY (UserId, RoleId),
    CONSTRAINT FK_UserRoles_Users FOREIGN KEY (UserId) REFERENCES Users(UserId),
    CONSTRAINT FK_UserRoles_Roles FOREIGN KEY (RoleId) REFERENCES Roles(RoleId)
);

/* =========================
   FLEET: vehicles, batteries, maintenance
   ========================= */

-- Hubs are physical depots where vehicles charge and dispatch
CREATE TABLE Hubs (
    HubId            INT IDENTITY(1,1) PRIMARY KEY,
    CityId           INT                NOT NULL,
    Name             NVARCHAR(120)      NOT NULL,
    AddressId        BIGINT             NOT NULL,
    IsActive         BIT                NOT NULL CONSTRAINT DF_Hubs_IsActive DEFAULT(1),
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Hubs_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_Hubs UNIQUE (CityId, Name),
    CONSTRAINT FK_Hubs_Cities FOREIGN KEY (CityId) REFERENCES Cities(CityId),
    CONSTRAINT FK_Hubs_Addresses FOREIGN KEY (AddressId) REFERENCES Addresses(AddressId)
);

-- Drone and scooter model catalogs keep specs consistent
CREATE TABLE DroneModels (
    DroneModelId     INT IDENTITY(1,1) PRIMARY KEY,
    Name             NVARCHAR(120)      NOT NULL,
    MaxPayloadKg     DECIMAL(6,2)       NOT NULL,
    RangeKm          DECIMAL(6,2)       NOT NULL,
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_DroneModels_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_DroneModels_Name UNIQUE (Name)
);

-- Scooter models for ground micro-mobility
CREATE TABLE ScooterModels (
    ScooterModelId   INT IDENTITY(1,1) PRIMARY KEY,
    Name             NVARCHAR(120)      NOT NULL,
    RangeKm          DECIMAL(6,2)       NOT NULL,
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_ScooterModels_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_ScooterModels_Name UNIQUE (Name)
);

-- Vehicles abstract over drones and scooters via a type discriminator
CREATE TABLE Vehicles (
    VehicleId        INT IDENTITY(1,1) PRIMARY KEY,
    HubId            INT                NOT NULL,
    Type             NVARCHAR(20)       NOT NULL, -- 'Drone' or 'Scooter'
    DroneModelId     INT                NULL,
    ScooterModelId   INT                NULL,
    SerialNumber     NVARCHAR(120)      NOT NULL,
    Status           NVARCHAR(20)       NOT NULL, -- 'Active','Maintenance','Retired'
    BatteryPct       TINYINT            NOT NULL CONSTRAINT DF_Vehicles_Battery DEFAULT(100),
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Vehicles_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_Vehicles_Serial UNIQUE (SerialNumber),
    CONSTRAINT CK_Vehicles_Type CHECK (Type IN (N'Drone', N'Scooter')),
    CONSTRAINT CK_Vehicles_Status CHECK (Status IN (N'Active', N'Maintenance', N'Retired')),
    CONSTRAINT FK_Vehicles_Hubs FOREIGN KEY (HubId) REFERENCES Hubs(HubId),
    CONSTRAINT FK_Vehicles_DroneModel FOREIGN KEY (DroneModelId) REFERENCES DroneModels(DroneModelId),
    CONSTRAINT FK_Vehicles_ScooterModel FOREIGN KEY (ScooterModelId) REFERENCES ScooterModels(ScooterModelId),
    CONSTRAINT CK_Vehicles_ModelRef CHECK (
        (Type = N'Drone'   AND DroneModelId   IS NOT NULL AND ScooterModelId IS NULL) OR
        (Type = N'Scooter' AND ScooterModelId IS NOT NULL AND DroneModelId   IS NULL)
    )
);

-- Swappable batteries are tracked to reduce downtime and for safety recalls
CREATE TABLE VehicleBatteries (
    BatteryId        INT IDENTITY(1,1) PRIMARY KEY,
    VehicleId        INT                NOT NULL,
    SerialNumber     NVARCHAR(120)      NOT NULL,
    HealthPct        TINYINT            NOT NULL CONSTRAINT DF_VB_Health DEFAULT(100),
    CycleCount       INT                NOT NULL CONSTRAINT DF_VB_Cycles DEFAULT(0),
    InstalledAt      DATETIME2(3)       NOT NULL CONSTRAINT DF_VB_InstalledAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_VB_Serial UNIQUE (SerialNumber),
    CONSTRAINT FK_VB_Vehicles FOREIGN KEY (VehicleId) REFERENCES Vehicles(VehicleId)
);

-- Maintenance orders capture planned corrective or preventive work
CREATE TABLE MaintenanceOrders (
    MaintenanceOrderId INT IDENTITY(1,1) PRIMARY KEY,
    VehicleId        INT                NOT NULL,
    OpenedByUserId   INT                NOT NULL,
    Status           NVARCHAR(20)       NOT NULL, -- 'Open','InProgress','Closed'
    Priority         NVARCHAR(10)       NOT NULL, -- 'Low','Medium','High','Critical'
    OpenedAt         DATETIME2(3)       NOT NULL CONSTRAINT DF_MO_OpenedAt DEFAULT(SYSDATETIME()),
    ClosedAt         DATETIME2(3)       NULL,
    Notes            NVARCHAR(1000)     NULL,
    CONSTRAINT CK_MO_Status CHECK (Status IN (N'Open', N'InProgress', N'Closed')),
    CONSTRAINT CK_MO_Priority CHECK (Priority IN (N'Low', N'Medium', N'High', N'Critical')),
    CONSTRAINT FK_MO_Vehicles FOREIGN KEY (VehicleId) REFERENCES Vehicles(VehicleId),
    CONSTRAINT FK_MO_Users FOREIGN KEY (OpenedByUserId) REFERENCES Users(UserId)
);

-- Maintenance logs give a detailed audit trail per order
CREATE TABLE MaintenanceLogs (
    MaintenanceLogId INT IDENTITY(1,1) PRIMARY KEY,
    MaintenanceOrderId INT            NOT NULL,
    LoggedByUserId   INT              NOT NULL,
    EntryAt          DATETIME2(3)     NOT NULL CONSTRAINT DF_ML_EntryAt DEFAULT(SYSDATETIME()),
    Entry            NVARCHAR(2000)   NOT NULL,
    CONSTRAINT FK_ML_MO FOREIGN KEY (MaintenanceOrderId) REFERENCES MaintenanceOrders(MaintenanceOrderId),
    CONSTRAINT FK_ML_User FOREIGN KEY (LoggedByUserId) REFERENCES Users(UserId)
);

/* =========================
   COMMERCE: merchants and catalog
   ========================= */

-- Merchants are businesses that request deliveries
CREATE TABLE Merchants (
    MerchantId       INT IDENTITY(1,1) PRIMARY KEY,
    OrganizationId   INT                NOT NULL,
    DefaultCityId    INT                NOT NULL,
    ApiKey           UNIQUEIDENTIFIER   NOT NULL CONSTRAINT DF_Merchants_ApiKey DEFAULT(NEWID()),
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Merchants_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT FK_Merchants_Org FOREIGN KEY (OrganizationId) REFERENCES Organizations(OrganizationId),
    CONSTRAINT FK_Merchants_City FOREIGN KEY (DefaultCityId) REFERENCES Cities(CityId)
);

-- Catalog items represent SKUs merchants ship via the platform
CREATE TABLE CatalogItems (
    CatalogItemId    BIGINT IDENTITY(1,1) PRIMARY KEY,
    MerchantId       INT                NOT NULL,
    Sku              NVARCHAR(80)       NOT NULL,
    Name             NVARCHAR(200)      NOT NULL,
    WeightKg         DECIMAL(7,3)       NOT NULL,
    LengthCm         DECIMAL(7,2)       NULL,
    WidthCm          DECIMAL(7,2)       NULL,
    HeightCm         DECIMAL(7,2)       NULL,
    HazardClass      NVARCHAR(40)       NULL, -- e.g., 'None','Battery','Fragile'
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_CatalogItems_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_Catalog UNIQUE (MerchantId, Sku),
    CONSTRAINT FK_Catalog_Merchant FOREIGN KEY (MerchantId) REFERENCES Merchants(MerchantId)
);

/* =========================
   BILLING: customers, invoices, payments
   ========================= */

-- Customers are the paying party for orders
CREATE TABLE Customers (
    CustomerId       INT IDENTITY(1,1) PRIMARY KEY,
    PersonId         BIGINT             NULL,
    OrganizationId   INT                NULL,
    DefaultCurrency  CHAR(3)            NOT NULL,
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Customers_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT CK_Customers_Owner CHECK (
        (PersonId IS NOT NULL AND OrganizationId IS NULL) OR
        (PersonId IS NULL AND OrganizationId IS NOT NULL)
    ),
    CONSTRAINT FK_Customers_Person FOREIGN KEY (PersonId) REFERENCES Persons(PersonId),
    CONSTRAINT FK_Customers_Org FOREIGN KEY (OrganizationId) REFERENCES Organizations(OrganizationId)
);

-- Invoices summarize charges per customer
CREATE TABLE Invoices (
    InvoiceId        BIGINT IDENTITY(1,1) PRIMARY KEY,
    CustomerId       INT                NOT NULL,
    InvoiceNumber    NVARCHAR(40)       NOT NULL,
    Status           NVARCHAR(20)       NOT NULL, -- 'Draft','Open','Paid','Void'
    Currency         CHAR(3)            NOT NULL,
    IssueDate        DATE               NOT NULL,
    DueDate          DATE               NOT NULL,
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Invoices_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_Invoices_Number UNIQUE (InvoiceNumber),
    CONSTRAINT CK_Invoices_Status CHECK (Status IN (N'Draft', N'Open', N'Paid', N'Void')),
    CONSTRAINT FK_Invoices_Customer FOREIGN KEY (CustomerId) REFERENCES Customers(CustomerId)
);

-- Invoice lines hold the monetary breakdown
CREATE TABLE InvoiceLines (
    InvoiceLineId    BIGINT IDENTITY(1,1) PRIMARY KEY,
    InvoiceId        BIGINT             NOT NULL,
    Description      NVARCHAR(200)      NOT NULL,
    Quantity         DECIMAL(18,4)      NOT NULL,
    UnitPrice        DECIMAL(18,4)      NOT NULL,
    TaxRatePct       DECIMAL(5,2)       NOT NULL DEFAULT(0),
    LineTotal        AS (ROUND(Quantity * UnitPrice * (1 + TaxRatePct/100.0), 4)) PERSISTED,
    CONSTRAINT FK_InvoiceLines_Invoice FOREIGN KEY (InvoiceId) REFERENCES Invoices(InvoiceId)
);

-- Payments record applied amounts against invoices
CREATE TABLE Payments (
    PaymentId        BIGINT IDENTITY(1,1) PRIMARY KEY,
    InvoiceId        BIGINT             NOT NULL,
    Amount           DECIMAL(18,4)      NOT NULL,
    Method           NVARCHAR(20)       NOT NULL, -- 'Card','Wallet','Wire','Cash'
    ReceivedAt       DATETIME2(3)       NOT NULL CONSTRAINT DF_Payments_ReceivedAt DEFAULT(SYSDATETIME()),
    Reference        NVARCHAR(120)      NULL,
    CONSTRAINT CK_Payments_Method CHECK (Method IN (N'Card', N'Wallet', N'Wire', N'Cash')),
    CONSTRAINT FK_Payments_Invoice FOREIGN KEY (InvoiceId) REFERENCES Invoices(InvoiceId)
);

/* =========================
   DELIVERY: orders, packages, routing
   ========================= */

-- Orders are the top-level delivery intent from a merchant to a customer
CREATE TABLE Orders (
    OrderId          BIGINT IDENTITY(1,1) PRIMARY KEY,
    MerchantId       INT                NOT NULL,
    CustomerId       INT                NOT NULL,
    CityId           INT                NOT NULL,
    PickupAddressId  BIGINT             NOT NULL,
    DropoffAddressId BIGINT             NOT NULL,
    Status           NVARCHAR(20)       NOT NULL, -- 'Pending','Assigned','InTransit','Delivered','Canceled'
    RequestedAt      DATETIME2(3)       NOT NULL CONSTRAINT DF_Orders_RequestedAt DEFAULT(SYSDATETIME()),
    DeliveredAt      DATETIME2(3)       NULL,
    Notes            NVARCHAR(500)      NULL,
    CONSTRAINT CK_Orders_Status CHECK (Status IN (N'Pending', N'Assigned', N'InTransit', N'Delivered', N'Canceled')),
    CONSTRAINT FK_Orders_Merchant FOREIGN KEY (MerchantId) REFERENCES  Merchants(MerchantId),
    CONSTRAINT FK_Orders_Customer FOREIGN KEY (CustomerId) REFERENCES Customers(CustomerId),
    CONSTRAINT FK_Orders_City FOREIGN KEY (CityId) REFERENCES Cities(CityId),
    CONSTRAINT FK_Orders_Pickup FOREIGN KEY (PickupAddressId) REFERENCES Addresses(AddressId),
    CONSTRAINT FK_Orders_Dropoff FOREIGN KEY (DropoffAddressId) REFERENCES Addresses(AddressId)
);

-- Order items tie catalog SKUs to an order for weight and content tracking
CREATE TABLE OrderItems (
    OrderItemId      BIGINT IDENTITY(1,1) PRIMARY KEY,
    OrderId          BIGINT             NOT NULL,
    CatalogItemId    BIGINT             NOT NULL,
    Quantity         DECIMAL(18,4)      NOT NULL,
    DeclaredValue    DECIMAL(18,2)      NULL,
    CONSTRAINT FK_OrderItems_Order FOREIGN KEY (OrderId) REFERENCES Orders(OrderId),
    CONSTRAINT FK_OrderItems_Catalog FOREIGN KEY (CatalogItemId) REFERENCES CatalogItems(CatalogItemId)
);

-- Packages are physical units shipped; one order may produce many packages
CREATE TABLE Packages (
    PackageId        BIGINT IDENTITY(1,1) PRIMARY KEY,
    OrderId          BIGINT             NOT NULL,
    LabelCode        NVARCHAR(60)       NOT NULL,
    WeightKg         DECIMAL(7,3)       NOT NULL,
    HazardClass      NVARCHAR(40)       NULL,
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Packages_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT UQ_Packages_Label UNIQUE (LabelCode),
    CONSTRAINT FK_Packages_Order FOREIGN KEY (OrderId) REFERENCES Orders(OrderId)
);

-- Routes are optimized paths operated by a specific vehicle
CREATE TABLE Routes (
    RouteId          BIGINT IDENTITY(1,1) PRIMARY KEY,
    CityId           INT                NOT NULL,
    VehicleId        INT                NOT NULL,
    PlannedStartAt   DATETIME2(3)       NOT NULL,
    PlannedEndAt     DATETIME2(3)       NULL,
    Status           NVARCHAR(20)       NOT NULL, -- 'Planned','Live','Completed','Aborted'
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Routes_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT CK_Routes_Status CHECK (Status IN (N'Planned', N'Live', N'Completed', N'Aborted')),
    CONSTRAINT FK_Routes_City FOREIGN KEY (CityId) REFERENCES Cities(CityId),
    CONSTRAINT FK_Routes_Vehicle FOREIGN KEY (VehicleId) REFERENCES Vehicles(VehicleId)
);

-- Each route stop represents a pickup or dropoff with sequencing
CREATE TABLE RouteStops (
    RouteStopId      BIGINT IDENTITY(1,1) PRIMARY KEY,
    RouteId          BIGINT             NOT NULL,
    SequenceNr       INT                NOT NULL,
    AddressId        BIGINT             NOT NULL,
    Purpose          NVARCHAR(20)       NOT NULL, -- 'Pickup','Dropoff'
    EtaAt            DATETIME2(3)       NULL,
    EtfAt            DATETIME2(3)       NULL,
    CONSTRAINT UQ_RouteStops UNIQUE (RouteId, SequenceNr),
    CONSTRAINT CK_RouteStops_Purpose CHECK (Purpose IN (N'Pickup', N'Dropoff')),
    CONSTRAINT FK_RouteStops_Route FOREIGN KEY (RouteId) REFERENCES Routes(RouteId),
    CONSTRAINT FK_RouteStops_Address FOREIGN KEY (AddressId) REFERENCES  Addresses(AddressId)
);

-- Assignments link orders/packages to specific route stops
CREATE TABLE Assignments (
    AssignmentId     BIGINT IDENTITY(1,1) PRIMARY KEY,
    RouteStopId      BIGINT             NOT NULL,
    OrderId          BIGINT             NOT NULL,
    PackageId        BIGINT             NULL,
    CreatedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_Assignments_CreatedAt DEFAULT(SYSDATETIME()),
    CONSTRAINT FK_Assignments_Stop FOREIGN KEY (RouteStopId) REFERENCES RouteStops(RouteStopId),
    CONSTRAINT FK_Assignments_Order FOREIGN KEY (OrderId) REFERENCES Orders(OrderId),
    CONSTRAINT FK_Assignments_Package FOREIGN KEY (PackageId) REFERENCES Packages(PackageId)
);

-- Proof-of-delivery closes the loop with signatures or photos
CREATE TABLE ProofsOfDelivery (
    PodId            BIGINT IDENTITY(1,1) PRIMARY KEY,
    OrderId          BIGINT             NOT NULL,
    CapturedByUserId INT                NOT NULL,
    CapturedAt       DATETIME2(3)       NOT NULL CONSTRAINT DF_POD_CapturedAt DEFAULT(SYSDATETIME()),
    Method           NVARCHAR(20)       NOT NULL, -- 'Signature','Photo','Pin'
    ArtifactUrl      NVARCHAR(400)      NULL,
    CONSTRAINT CK_POD_Method CHECK (Method IN (N'Signature', N'Photo', N'Pin')),
    CONSTRAINT FK_POD_Order FOREIGN KEY (OrderId) REFERENCES Orders(OrderId),
    CONSTRAINT FK_POD_User FOREIGN KEY (CapturedByUserId) REFERENCES Users(UserId)
);

/* =========================
   ANALYTICS: event firehose
   ========================= */

-- Analytics events capture immutable, schemalite telemetry with typed columns for common fields
CREATE TABLE Events (
    EventId          BIGINT IDENTITY(1,1) PRIMARY KEY,
    OccurredAt       DATETIME2(3)       NOT NULL CONSTRAINT DF_Events_OccurredAt DEFAULT(SYSDATETIME()),
    EventType        NVARCHAR(60)       NOT NULL,
    ActorUserId      INT                NULL,
    EntityType       NVARCHAR(40)       NULL,  -- e.g., 'Order','Vehicle'
    EntityIdBig      BIGINT             NULL,
    CityId           INT                NULL,
    PayloadJson      NVARCHAR(MAX)      NULL,
    CONSTRAINT FK_Events_User FOREIGN KEY (ActorUserId) REFERENCES Users(UserId),
    CONSTRAINT FK_Events_City FOREIGN KEY (CityId) REFERENCES Cities(CityId)
);

/* =========================
   SUPPORT: tickets and messages
   ========================= */

-- Support tickets unify merchant and customer issues
CREATE TABLE Tickets (
    TicketId         BIGINT IDENTITY(1,1) PRIMARY KEY,
    OpenedByUserId   INT                NOT NULL,
    RelatedOrderId   BIGINT             NULL,
    Status           NVARCHAR(20)       NOT NULL, -- 'Open','Pending','Resolved','Closed'
    Priority         NVARCHAR(10)       NOT NULL, -- 'Low','Medium','High','Urgent'
    Subject          NVARCHAR(200)      NOT NULL,
    OpenedAt         DATETIME2(3)       NOT NULL CONSTRAINT DF_Tickets_OpenedAt DEFAULT(SYSDATETIME()),
    ClosedAt         DATETIME2(3)       NULL,
    CONSTRAINT CK_Tickets_Status CHECK (Status IN (N'Open', N'Pending', N'Resolved', N'Closed')),
    CONSTRAINT CK_Tickets_Priority CHECK (Priority IN (N'Low', N'Medium', N'High', N'Urgent')),
    CONSTRAINT FK_Tickets_User FOREIGN KEY (OpenedByUserId) REFERENCES Users(UserId),
    CONSTRAINT FK_Tickets_Order FOREIGN KEY (RelatedOrderId) REFERENCES Orders(OrderId)
);

-- Ticket messages carry the actual conversation and audit trail
CREATE TABLE TicketMessages (
    TicketMessageId  BIGINT IDENTITY(1,1) PRIMARY KEY,
    TicketId         BIGINT             NOT NULL,
    SenderUserId     INT                NOT NULL,
    SentAt           DATETIME2(3)       NOT NULL CONSTRAINT DF_TicketMessages_SentAt DEFAULT(SYSDATETIME()),
    Body             NVARCHAR(2000)     NOT NULL,
    CONSTRAINT FK_TicketMessages_Ticket FOREIGN KEY (TicketId) REFERENCES Tickets(TicketId),
    CONSTRAINT FK_TicketMessages_User FOREIGN KEY (SenderUserId) REFERENCES Users(UserId)
);
/* =========================
   AUDIT: change history
   ========================= */

-- Change log tracks row-level mutations for compliance
CREATE TABLE  ChangeLog (
    ChangeId         BIGINT IDENTITY(1,1) PRIMARY KEY,
    TableName        NVARCHAR(160)      NOT NULL,
    PrimaryKeyJson   NVARCHAR(500)      NOT NULL,
    Operation        NVARCHAR(10)       NOT NULL, -- 'INSERT','UPDATE','DELETE'
    ChangedByUserId  INT                NULL,
    ChangedAt        DATETIME2(3)       NOT NULL CONSTRAINT DF_ChangeLog_ChangedAt DEFAULT(SYSDATETIME()),
    SnapshotJson     NVARCHAR(MAX)      NULL,
    CONSTRAINT CK_ChangeLog_Operation CHECK (Operation IN (N'INSERT', N'UPDATE', N'DELETE')),
    CONSTRAINT FK_ChangeLog_User FOREIGN KEY (ChangedByUserId) REFERENCES Users(UserId)
);

/* =========================
   Insertion Data into cities
   ========================= */

   INSERT INTO Cities (Name, CountryCode, TimezoneIana)
VALUES
(N'New York',       'US', N'America/New_York'),
(N'Los Angeles',    'US', N'America/Los_Angeles'),
(N'Chicago',        'US', N'America/Chicago'),
(N'Houston',        'US', N'America/Chicago'),
(N'Miami',          'US', N'America/New_York'),

(N'Toronto',        'CA', N'America/Toronto'),
(N'Vancouver',      'CA', N'America/Vancouver'),
(N'Montreal',       'CA', N'America/Toronto'),
(N'Ottawa',         'CA', N'America/Toronto'),
(N'Calgary',        'CA', N'America/Edmonton'),

(N'London',         'GB', N'Europe/London'),
(N'Manchester',     'GB', N'Europe/London'),
(N'Birmingham',     'GB', N'Europe/London'),
(N'Liverpool',      'GB', N'Europe/London'),
(N'Leeds',          'GB', N'Europe/London'),

(N'Paris',          'FR', N'Europe/Paris'),
(N'Lyon',           'FR', N'Europe/Paris'),
(N'Marseille',      'FR', N'Europe/Paris'),
(N'Toulouse',       'FR', N'Europe/Paris'),
(N'Nice',           'FR', N'Europe/Paris'),

(N'Berlin',         'DE', N'Europe/Berlin'),
(N'Munich',         'DE', N'Europe/Berlin'),
(N'Hamburg',        'DE', N'Europe/Berlin'),
(N'Cologne',        'DE', N'Europe/Berlin'),
(N'Frankfurt',      'DE', N'Europe/Berlin'),

(N'Helsinki',       'FI', N'Europe/Helsinki'),
(N'Tampere',        'FI', N'Europe/Helsinki'),
(N'Turku',          'FI', N'Europe/Helsinki'),
(N'Vaasa',          'FI', N'Europe/Helsinki'),
(N'Oulu',           'FI', N'Europe/Helsinki');



/* =========================
   Insertion Data into Zones
   ========================= */
INSERT INTO Zones (CityId, Code, Name, PolygonWkt, IsRestricted)
VALUES
(1,  N'NYC-DT',   N'New York Downtown',      N'POLYGON((0 0,0 1,1 1,1 0,0 0))', 0),
(1,  N'NYC-MD',   N'New York Midtown',       N'POLYGON((1 1,1 2,2 2,2 1,1 1))', 0),

(2,  N'LA-CEN',   N'Los Angeles Central',    N'POLYGON((0 0,0 2,2 2,2 0,0 0))', 0),
(2,  N'LA-BEV',   N'Beverly Hills Zone',     N'POLYGON((2 2,2 3,3 3,3 2,2 2))', 0),

(3,  N'CHI-LP',   N'Chicago Lincoln Park',   N'POLYGON((0 0,0 1,1 1,1 0,0 0))', 0),
(3,  N'CHI-DT',   N'Chicago Downtown',       N'POLYGON((1 0,1 1,2 1,2 0,1 0))', 0),

(4,  N'HOU-MD',   N'Houston Medical District', N'POLYGON((0 0,0 1,1 1,1 0,0 0))', 0),
(4,  N'HOU-EN',   N'Houston Eastside',       N'POLYGON((1 1,1 2,2 2,2 1,1 1))', 0),

(5,  N'MIA-BCH',  N'Miami Beach',            N'POLYGON((0 0,0 1,1 1,1 0,0 0))', 0),
(5,  N'MIA-DT',   N'Miami Downtown',         N'POLYGON((1 0,1 1,2 1,2 0,1 0))', 0),

(6,  N'TOR-DT',   N'Toronto Downtown',       N'POLYGON((0 0,0 1,1 1,1 0,0 0))', 0),
(6,  N'TOR-NR',   N'Toronto North York',     N'POLYGON((1 1,1 2,2 2,2 1,1 1))', 0),

(7,  N'VAN-CEN',  N'Vancouver Central',      N'POLYGON((0 0,0 2,2 2,2 0,0 0))', 0),
(7,  N'VAN-RMD',  N'Vancouver Richmond',     N'POLYGON((2 2,2 3,3 3,3 2,2 2))', 0),

(8,  N'MTL-OLD',  N'Montreal Old Port',      N'POLYGON((0 0,0 1,1 1,1 0,0 0))', 0),
(8,  N'MTL-DT',   N'Montreal Downtown',      N'POLYGON((1 0,1 1,2 1,2 0,1 0))', 0),

(9,  N'OTT-CEN',  N'Ottawa Centre',          N'POLYGON((0 0,0 1,1 1,1 0,0 0))', 0),
(9,  N'OTT-KAN',  N'Ottawa Kanata',          N'POLYGON((1 1,1 2,2 2,2 1,1 1))', 0),

(10, N'CAL-DT',   N'Calgary Downtown',       N'POLYGON((0 0,0 1,1 1,1 0,0 0))', 0),
(10, N'CAL-NE',   N'Calgary Northeast',      N'POLYGON((1 0,1 1,2 1,2 0,1 0))', 0),

(11, N'LDN-CEN',  N'London Central',         N'POLYGON((0 0,0 2,2 2,2 0,0 0))', 0),
(11, N'LDN-WST',  N'London West End',        N'POLYGON((2 2,2 3,3 3,3 2,2 2))', 0);
/* =========================
   Insertion Data into Addresses
   ========================= */
INSERT INTO Addresses (CityId, Line1, Line2, PostalCode, Latitude, Longitude, PlaceLabel)
VALUES
(1,  N'350 5th Ave',       N'Floor 50', N'10118', 40.748817, -73.985428, N'Empire State Building'),
(2,  N'6801 Hollywood Blvd', NULL, N'90028', 34.101558, -118.339493, N'Hollywood Walk of Fame'),
(3,  N'233 S Wacker Dr',   NULL, N'60606', 41.878876, -87.635915, N'Willis Tower'),
(4,  N'1500 McKinney St',  NULL, N'77010', 29.752300, -95.357300, N'Discovery Green Park'),
(5,  N'401 Biscayne Blvd', NULL, N'33132', 25.777300, -80.186700, N'Bayside Marketplace'),

(6,  N'290 Bremner Blvd',  NULL, N'M5V 3L9', 43.642566, -79.387057, N'CN Tower'),
(7,  N'650 W 41st Ave',    NULL, N'V5Z 2M9', 49.232400, -123.118800, N'Queen Elizabeth Park'),
(8,  N'1000 Rue De La Gauchetière', NULL, N'H3B 4W5', 45.496000, -73.570000, N'Montreal Central Station'),
(9,  N'111 Wellington St', NULL, N'K1A 0A6', 45.423600, -75.700900, N'Parliament Hill'),
(10, N'1410 Olympic Way SE', NULL, N'T2G 2W1', 51.037400, -114.054300, N'Scotiabank Saddledome'),

(11, N'Westminster Abbey', NULL, N'SW1P 3PA', 51.499300, -0.127300, N'Abbey'),
(12, N'Old Trafford Stadium', NULL, N'M16 0RA', 53.463100, -2.291300, N'Football Ground'),
(13, N'Broad St',          NULL, N'B1 2EA', 52.478600, -1.908900, N'ICC Birmingham'),
(14, N'Lime St',           NULL, N'L1 1JD', 53.407600, -2.977900, N'Liverpool Lime Street Station'),
(15, N'Millennium Square', NULL, N'LS2 3AD', 53.802000, -1.548600, N'City Centre'),

(16, N'5 Avenue Anatole',  NULL, N'75007', 48.858400, 2.294500, N'Eiffel Tower'),
(17, N'Place Bellecour',   NULL, N'69002', 45.757800, 4.832000, N'Bellecour Square'),
(18, N'La Canebière',      NULL, N'13001', 43.296500, 5.369800, N'Old Port'),
(19, N'Capitole de Toulouse', NULL, N'31000', 43.604700, 1.444200, N'City Hall'),
(20, N'Promenade des Anglais', NULL, N'06000', 43.695000, 7.265000, N'Beachfront'),

(21, N'Brandenburg Gate',  NULL, N'10117', 52.516300, 13.377700, N'Gate'),
(22, N'Marienplatz',       NULL, N'80331', 48.137100, 11.575400, N'Central Square'),
(23, N'Speicherstadt',     NULL, N'20457', 53.543000, 9.988000, N'Warehouse District'),
(24, N'Cologne Cathedral', NULL, N'50667', 50.941300, 6.958300, N'Dom'),
(25, N'Römerberg',         NULL, N'60311', 50.110600, 8.682100, N'Historic Centre'),

(26, N'Mannerheimintie 13', NULL, N'00100', 60.169900, 24.938400, N'Central Helsinki'),
(27, N'Hämeenkatu 20',     NULL, N'33200', 61.497800, 23.761000, N'Tampere Main Street'),
(28, N'Eerikinkatu 15',    NULL, N'20100', 60.451800, 22.266600, N'Turku Centre'),
(29, N'Vaasanpuistikko 2', NULL, N'65100', 63.095100, 21.615800, N'Vaasa Market Square'),
(30, N'Torikatu 10',       NULL, N'90100', 65.012100, 25.465100, N'Oulu Centre');

/* =========================
   Insertion Data into Organizations
   ========================= */
INSERT INTO Organizations (Name, Type)
VALUES
(N'Urban Fresh Foods',         N'Merchant'),
(N'CityRide Mobility',          N'Merchant'),
(N'SkyDrop Deliveries',         N'Merchant'),
(N'GreenWheel Scooters',        N'Merchant'),
(N'Cafe Bonjour',               N'Merchant'),

(N'TechNova Partners',          N'Partner'),
(N'Global Logistics Alliance',  N'Partner'),
(N'Finland Trade Council',      N'Partner'),
(N'EuroRetail Network',         N'Partner'),
(N'CloudSys Integrations',      N'Partner'),

(N'Internal Finance Dept',      N'Internal'),
(N'Internal IT Support',        N'Internal'),
(N'Internal HR Division',       N'Internal'),
(N'Internal Operations Hub',    N'Internal'),
(N'Internal Compliance Unit',   N'Internal'),

(N'FreshMart Supermarkets',     N'Merchant'),
(N'GoClean Energy',             N'Merchant'),
(N'Metro Electronics',          N'Merchant'),
(N'VeloCity Bikes',             N'Merchant'),
(N'HappyPets Store',            N'Merchant'),

(N'LogiLink Partners',          N'Partner'),
(N'DigitalPay Systems',         N'Partner'),
(N'SmartFleet Associates',      N'Partner'),
(N'Global Courier Group',       N'Partner'),
(N'MegaCloud Hosting',          N'Partner'),

(N'Internal Security Team',     N'Internal'),
(N'Internal R&D Unit',          N'Internal'),
(N'Internal Training Center',   N'Internal'),
(N'Internal Analytics Cell',    N'Internal'),
(N'Internal Project Office',    N'Internal');


/* =========================
   Insertion Data into Persons
   ========================= */

INSERT INTO Persons (FirstName, LastName, Email, Phone)
VALUES
(N'John',     N'Smith',      N'john.smith@example.com',      N'+1-202-555-0101'),
(N'Emma',     N'Johnson',    N'emma.johnson@example.com',    N'+1-202-555-0102'),
(N'Oliver',   N'Williams',   N'oliver.williams@example.com', N'+1-202-555-0103'),
(N'Sophia',   N'Brown',      N'sophia.brown@example.com',    N'+1-202-555-0104'),
(N'Liam',     N'Jones',      N'liam.jones@example.com',      N'+1-202-555-0105'),

(N'Ava',      N'Miller',     N'ava.miller@example.com',      N'+1-202-555-0106'),
(N'Noah',     N'Davis',      N'noah.davis@example.com',      N'+1-202-555-0107'),
(N'Isabella', N'Garcia',     N'isabella.garcia@example.com', N'+1-202-555-0108'),
(N'Ethan',    N'Martinez',   N'ethan.martinez@example.com',  N'+1-202-555-0109'),
(N'Mia',      N'Rodriguez',  N'mia.rodriguez@example.com',   N'+1-202-555-0110'),

(N'Lucas',    N'Hernandez',  N'lucas.hernandez@example.com', N'+1-202-555-0111'),
(N'Amelia',   N'Lopez',      N'amelia.lopez@example.com',    N'+1-202-555-0112'),
(N'Mason',    N'Gonzalez',   N'mason.gonzalez@example.com',  N'+1-202-555-0113'),
(N'Harper',   N'Wilson',     N'harper.wilson@example.com',   N'+1-202-555-0114'),
(N'James',    N'Anderson',   N'james.anderson@example.com',  N'+1-202-555-0115'),

(N'Evelyn',   N'Thomas',     N'evelyn.thomas@example.com',   N'+1-202-555-0116'),
(N'Benjamin', N'Taylor',     N'benjamin.taylor@example.com', N'+1-202-555-0117'),
(N'Charlotte',N'Moore',      N'charlotte.moore@example.com', N'+1-202-555-0118'),
(N'Henry',    N'Jackson',    N'henry.jackson@example.com',   N'+1-202-555-0119'),
(N'Abigail',  N'Martin',     N'abigail.martin@example.com',  N'+1-202-555-0120'),

(N'Alexander',N'Lee',        N'alexander.lee@example.com',   N'+1-202-555-0121'),
(N'Emily',    N'Perez',      N'emily.perez@example.com',     N'+1-202-555-0122'),
(N'William',  N'White',      N'william.white@example.com',   N'+1-202-555-0123'),
(N'Grace',    N'Harris',     N'grace.harris@example.com',    N'+1-202-555-0124'),
(N'Daniel',   N'Clark',      N'daniel.clark@example.com',    N'+1-202-555-0125'),

(N'Victoria', N'Lewis',      N'victoria.lewis@example.com',  N'+1-202-555-0126'),
(N'Sebastian',N'Walker',     N'sebastian.walker@example.com',N'+1-202-555-0127'),
(N'Chloe',    N'Young',      N'chloe.young@example.com',     N'+1-202-555-0128'),
(N'Jack',     N'Allen',      N'jack.allen@example.com',      N'+1-202-555-0129'),
(N'Lily',     N'King',       N'lily.king@example.com',       N'+1-202-555-0130');

/* =========================
  insert data into SECURITY: users and access
   =========================
  */


INSERT INTO Users (PersonId, Username, PasswordHash)
VALUES
(1,  N'johnsmith',      CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@101'))),
(2,  N'emmajohnson',    CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@102'))),
(3,  N'oliverw',        CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@103'))),
(4,  N'sophiab',        CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@104'))),
(5,  N'liamjones',      CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@105'))),

(6,  N'avamiller',      CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@106'))),
(7,  N'noahdavis',      CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@107'))),
(8,  N'isagarcia',      CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@108'))),
(9,  N'ethanmartinez',  CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@109'))),
(10, N'miarodriguez',   CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@110'))),

(11, N'lucash',         CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@111'))),
(12, N'amelialopez',    CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@112'))),
(13, N'masong',         CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@113'))),
(14, N'harperwilson',   CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@114'))),
(15, N'janderson',      CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@115'))),

(16, N'evelynthomas',   CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@116'))),
(17, N'bentaylor',      CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@117'))),
(18, N'charlmoore',     CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@118'))),
(19, N'henryjackson',   CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@119'))),
(20, N'abimartin',      CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@120'))),

(21, N'alexlee',        CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@121'))),
(22, N'emilyperez',     CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@122'))),
(23, N'willwhite',      CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@123'))),
(24, N'graceharris',    CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@124'))),
(25, N'danclark',       CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@125'))),

(26, N'vlewis',         CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@126'))),
(27, N'sebwalker',      CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@127'))),
(28, N'chloeyoung',     CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@128'))),
(29, N'jackallen',      CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@129'))),
(30, N'lilyking',       CONVERT(VARBINARY(256), HASHBYTES('SHA2_256', 'Pass@130')));


INSERT INTO Roles (Name)
VALUES
(N'Admin'),
(N'SuperUser'),
(N'MerchantManager'),
(N'PartnerManager'),
(N'InternalStaff'),
(N'Customer'),
(N'DeliveryCourier'),
(N'SupportAgent'),
(N'Analyst'),
(N'Auditor');


INSERT INTO UserRoles (UserId, RoleId)
VALUES
(1, 1), (1, 6), (1, 7),
(2, 2), (2, 6), (2, 8),
(3, 3), (3, 6), (3, 9),
(4, 4), (4, 6), (4, 7),
(5, 5), (5, 6), (5, 10),
(6, 1), (6, 6), (6, 8),
(7, 2), (7, 6), (7, 7),
(8, 3), (8, 6), (8, 9),
(9, 4), (9, 6), (9, 10),
(10, 5), (10, 6), (10, 7),
(11, 1), (11, 6), (11, 9),
(12, 2), (12, 6), (12, 7),
(13, 3), (13, 6), (13, 8),
(14, 4), (14, 6), (14, 9),
(15, 5), (15, 6), (15, 10),
(16, 1), (16, 6), (16, 7),
(17, 2), (17, 6), (17, 8),
(18, 3), (18, 6), (18, 9),
(19, 4), (19, 6), (19, 7),
(20, 5), (20, 6), (20, 10),
(21, 1), (21, 6), (21, 9),
(22, 2), (22, 6), (22, 7),
(23, 3), (23, 6), (23, 8),
(24, 4), (24, 6), (24, 9),
(25, 5), (25, 6), (25, 10),
(26, 1), (26, 6), (26, 7),
(27, 2), (27, 6), (27, 8),
(28, 3), (28, 6), (28, 9),
(29, 4), (29, 6), (29, 7),
(30, 5), (30, 6), (30, 10);



/* =========================
  insert data into  FLEET: vehicles, batteries, maintenance
   ========================= */

   INSERT INTO Hubs (CityId, Name, AddressId)
VALUES
(1,  N'New York Central Hub',      1),
(2,  N'Los Angeles West Hub',      2),
(3,  N'Chicago Downtown Hub',      3),
(4,  N'Houston Energy Corridor',   4),
(5,  N'Miami Beach Hub',           5),

(6,  N'Toronto Main Hub',          6),
(7,  N'Vancouver Pacific Hub',     7),
(8,  N'Montreal East Hub',         8),
(9,  N'Ottawa Capital Hub',        9),
(10, N'Calgary Central Hub',      10);



INSERT INTO DroneModels (Name, MaxPayloadKg, RangeKm)
VALUES
(N'SkyCarrier X1',       5.00, 15.00),
(N'SkyCarrier X2',       6.50, 18.00),
(N'SkyCarrier X3',       7.20, 20.00),
(N'SkyCarrier X4',       8.00, 22.00),
(N'SkyCarrier X5',       9.50, 25.00),

(N'AirDropper A1',       2.50, 10.00),
(N'AirDropper A2',       3.00, 12.00),
(N'AirDropper A3',       3.50, 14.00),
(N'AirDropper A4',       4.00, 16.00),
(N'AirDropper A5',       4.50, 18.00),

(N'FalconPro 100',       12.00, 30.00),
(N'FalconPro 200',       14.00, 35.00),
(N'FalconPro 300',       16.00, 40.00),
(N'FalconPro 400',       18.00, 45.00),
(N'FalconPro 500',       20.00, 50.00),

(N'DeliveryHawk D1',     8.00, 28.00),
(N'DeliveryHawk D2',     9.00, 30.00),
(N'DeliveryHawk D3',     10.00, 32.00),
(N'DeliveryHawk D4',     11.00, 34.00),
(N'DeliveryHawk D5',     12.00, 36.00),

(N'UrbanFlyer U1',       5.00, 20.00),
(N'UrbanFlyer U2',       6.00, 22.00),
(N'UrbanFlyer U3',       7.00, 24.00),
(N'UrbanFlyer U4',       8.00, 26.00),
(N'UrbanFlyer U5',       9.00, 28.00),

(N'MegaLift M1',         15.00, 20.00),
(N'MegaLift M2',         18.00, 22.00),
(N'MegaLift M3',         20.00, 25.00),
(N'MegaLift M4',         22.00, 28.00),
(N'MegaLift M5',         25.00, 30.00);

INSERT INTO ScooterModels (Name, RangeKm)
VALUES
(N'CityScoot S1',    20.00),
(N'CityScoot S2',    25.00),
(N'CityScoot S3',    30.00),
(N'CityScoot S4',    35.00),
(N'CityScoot S5',    40.00),

(N'UrbanRider U1',   22.00),
(N'UrbanRider U2',   28.00),
(N'UrbanRider U3',   34.00),
(N'UrbanRider U4',   38.00),
(N'UrbanRider U5',   42.00),

(N'MetroMove M1',    26.00),
(N'MetroMove M2',    32.00),
(N'MetroMove M3',    36.00),
(N'MetroMove M4',    45.00),
(N'MetroMove M5',    50.00),

(N'EcoWheel E1',     24.00),
(N'EcoWheel E2',     29.00),
(N'EcoWheel E3',     37.00),
(N'EcoWheel E4',     44.00),
(N'EcoWheel E5',     48.00),

(N'SwiftRide SR1',   30.00),
(N'SwiftRide SR2',   35.00),
(N'SwiftRide SR3',   41.00),
(N'SwiftRide SR4',   47.00),
(N'SwiftRide SR5',   55.00),

(N'GlideX G1',       33.00),
(N'GlideX G2',       39.00),
(N'GlideX G3',       46.00),
(N'GlideX G4',       60.00),
(N'GlideX G5',       75.00);


INSERT INTO Vehicles (HubId, Type, DroneModelId, ScooterModelId, SerialNumber, Status)
VALUES
(1,  N'Drone',   1,  NULL, N'DRONE-001-AX', N'Active'),
(1,  N'Drone',   2,  NULL, N'DRONE-002-BY', N'Maintenance'),
(2,  N'Drone',   3,  NULL, N'DRONE-003-CZ', N'Active'),
(2,  N'Drone',   4,  NULL, N'DRONE-004-DX', N'Active'),
(3,  N'Drone',   5,  NULL, N'DRONE-005-EY', N'Retired'),
(3,  N'Drone',   6,  NULL, N'DRONE-006-FZ', N'Active'),
(4,  N'Drone',   7,  NULL, N'DRONE-007-GX', N'Active'),
(4,  N'Drone',   8,  NULL, N'DRONE-008-HY', N'Maintenance'),
(5,  N'Drone',   9,  NULL, N'DRONE-009-IZ', N'Active'),
(5,  N'Drone',   10, NULL, N'DRONE-010-JX', N'Active'),
(6,  N'Drone',   11, NULL, N'DRONE-011-KY', N'Active'),
(6,  N'Drone',   12, NULL, N'DRONE-012-LZ', N'Maintenance'),
(7,  N'Drone',   13, NULL, N'DRONE-013-MX', N'Active'),
(7,  N'Drone',   14, NULL, N'DRONE-014-NY', N'Active'),
(8,  N'Drone',   15, NULL, N'DRONE-015-OZ', N'Retired'),
(8,  N'Scooter', NULL, 1,  N'SCOOT-016-A1', N'Active'),
(9,  N'Scooter', NULL, 2,  N'SCOOT-017-B2', N'Active'),
(9,  N'Scooter', NULL, 3,  N'SCOOT-018-C3', N'Maintenance'),
(10, N'Scooter', NULL, 4,  N'SCOOT-019-D4', N'Active'),
(10, N'Scooter', NULL, 5,  N'SCOOT-020-E5', N'Retired'),
(1,  N'Scooter', NULL, 6,  N'SCOOT-021-F6', N'Active'),
(2,  N'Scooter', NULL, 7,  N'SCOOT-022-G7', N'Active'),
(3,  N'Scooter', NULL, 8,  N'SCOOT-023-H8', N'Maintenance'),
(4,  N'Scooter', NULL, 9,  N'SCOOT-024-I9', N'Active'),
(5,  N'Scooter', NULL, 10, N'SCOOT-025-J0', N'Active'),
(6,  N'Scooter', NULL, 11, N'SCOOT-026-K1', N'Active'),
(7,  N'Scooter', NULL, 12, N'SCOOT-027-L2', N'Active'),
(8,  N'Scooter', NULL, 13, N'SCOOT-028-M3', N'Retired'),
(9,  N'Scooter', NULL, 14, N'SCOOT-029-N4', N'Active'),
(10, N'Scooter', NULL, 15, N'SCOOT-030-O5', N'Maintenance');


INSERT INTO VehicleBatteries (VehicleId, SerialNumber, HealthPct, CycleCount)
VALUES
(1,  N'BAT-001-A1', 95,  12),
(2,  N'BAT-002-B2', 88,  20),
(3,  N'BAT-003-C3', 92,  15),
(4,  N'BAT-004-D4', 97,   8),
(5,  N'BAT-005-E5', 85,  25),
(6,  N'BAT-006-F6', 90,  18),
(7,  N'BAT-007-G7', 93,  10),
(8,  N'BAT-008-H8', 80,  30),
(9,  N'BAT-009-I9', 96,   7),
(10, N'BAT-010-J0', 89,  22),
(11, N'BAT-011-K1', 94,  14),
(12, N'BAT-012-L2', 91,  16),
(13, N'BAT-013-M3', 87,  24),
(14, N'BAT-014-N4', 98,   5),
(15, N'BAT-015-O5', 82,  28),
(16, N'BAT-016-P6', 95,  12),
(17, N'BAT-017-Q7', 90,  18),
(18, N'BAT-018-R8', 92,  15),
(19, N'BAT-019-S9', 85,  26),
(20, N'BAT-020-T0', 97,   9),
(21, N'BAT-021-U1', 94,  13),
(22, N'BAT-022-V2', 89,  21),
(23, N'BAT-023-W3', 91,  17),
(24, N'BAT-024-X4', 96,   6),
(25, N'BAT-025-Y5', 83,  27),

(26, N'BAT-026-Z6', 95,  12),
(27, N'BAT-027-A7', 88,  20),
(28, N'BAT-028-B8', 92,  14),
(29, N'BAT-029-C9', 97,   8),
(30, N'BAT-030-D0', 86,  23);


INSERT INTO MaintenanceOrders (VehicleId, OpenedByUserId, Status, Priority, Notes)
VALUES
(1,  1,  N'Open',        N'High',     N'Battery health dropped below 85%'),
(2,  2,  N'InProgress',  N'Medium',   N'Firmware update in progress'),
(3,  3,  N'Closed',      N'Low',      N'Routine inspection completed'),
(4,  4,  N'Open',        N'Critical', N'Motor malfunction detected'),
(5,  5,  N'Closed',      N'Medium',   N'Brake adjustment done'),
(6,  6,  N'InProgress',  N'High',     N'GPS calibration ongoing'),
(7,  7,  N'Open',        N'Low',      N'Cosmetic scratches reported'),
(8,  8,  N'Closed',      N'Medium',   N'Software patch applied'),
(9,  9,  N'InProgress',  N'High',     N'Battery replacement ongoing'),
(10, 10, N'Open',        N'Critical', N'Signal loss issue'),
(11, 1,  N'Closed',      N'Low',      N'Annual inspection completed'),
(12, 2,  N'InProgress',  N'Medium',   N'Wheel alignment being fixed'),
(13, 3,  N'Open',        N'High',     N'Unexpected shutdown issue'),
(14, 4,  N'Closed',      N'Medium',   N'Lighting system fixed'),
(15, 5,  N'Open',        N'Critical', N'Collision damage assessment'),
(16, 6,  N'InProgress',  N'High',     N'Battery overheating issue'),
(17, 7,  N'Closed',      N'Low',      N'Tire replacement done'),
(18, 8,  N'Open',        N'Medium',   N'Loose handlebar reported'),
(19, 9,  N'InProgress',  N'Critical', N'Engine noise investigation'),
(20, 10, N'Closed',      N'High',     N'Gyroscope recalibrated'),
(21, 1,  N'Open',        N'Low',      N'General cleaning scheduled'),
(22, 2,  N'InProgress',  N'Medium',   N'Sensor recalibration ongoing'),
(23, 3,  N'Closed',      N'High',     N'Brake pads replaced'),
(24, 4,  N'Open',        N'Critical', N'Main controller issue'),
(25, 5,  N'InProgress',  N'Medium',   N'Firmware rollout in progress'),
(26, 6,  N'Closed',      N'Low',      N'Inspection cleared'),
(27, 7,  N'Open',        N'High',     N'Charging port damaged'),
(28, 8,  N'InProgress',  N'Medium',   N'Software diagnostics running'),
(29, 9,  N'Closed',      N'Critical', N'Battery pack replaced'),
(30, 10, N'Open',        N'High',     N'Motor overheating warning');



INSERT INTO MaintenanceLogs (MaintenanceOrderId, LoggedByUserId, Entry)
VALUES
(1,  2,  N'Initial diagnostics queued; battery health trend captured.'),
(2,  3,  N'Firmware package downloaded; device in update mode.'),
(3,  4,  N'QC sign-off obtained; no anomalies found.'),
(4,  5,  N'Motor controller error codes collected; parts on order.'),
(5,  6,  N'Brake tension adjusted; test ride passed.'),
(6,  7,  N'GPS lock improved after calibration; monitoring drift.'),
(7,  8,  N'Cosmetic assessment recorded; no safety impact.'),
(8,  9,  N'Patch v2.1 applied; reboot successful.'),
(9,  10, N'Battery swap in progress; thermal checks pending.'),
(10, 1,  N'RF antenna reseated; signal quality re-tested.'),

(11, 2,  N'Annual checklist completed; records archived.'),
(12, 3,  N'Wheel alignment corrected; vibration reduced.'),
(13, 4,  N'Crash logs exported; root cause under analysis.'),
(14, 5,  N'LED module replaced; draw within spec.'),
(15, 6,  N'Photo evidence captured; frame inspection scheduled.'),

(16, 7,  N'Thermal paste reapplied; fan curve updated.'),
(17, 8,  N'Tires replaced; pressure set to recommended PSI.'),
(18, 9,  N'Handlebar bolts retorqued; rattle resolved.'),
(19, 10, N'Engine acoustic profile recorded; bearing suspected.'),
(20, 1,  N'IMU recalibrated; drift minimized.'),

(21, 2,  N'Deep clean performed; corrosion check done.'),
(22, 3,  N'Sensor offsets recalculated; tolerance within range.'),
(23, 4,  N'Brake pads fitted; stopping distance verified.'),
(24, 5,  N'Controller reset attempted; escalation to L2.'),
(25, 6,  N'Firmware staged; rollback plan documented.'),

(26, 7,  N'Inspection cleared; no action needed.'),
(27, 8,  N'Charging port pins bent; replacement requested.'),
(28, 9,  N'Diagnostics completed; logs attached to ticket.'),
(29, 10, N'New battery pack validated; capacity test passed.'),
(30, 1,  N'Motor temp spike reproduced; airflow path reviewed.');


/* =========================
   COMMERCE: merchants and catalog
   ========================= */

   -- 10 merchants mapped to merchant organizations and cities
INSERT INTO Merchants (OrganizationId, DefaultCityId)
VALUES
(1,  1),   -- Urban Fresh Foods  -> New York
(2,  2),   -- CityRide Mobility   -> Los Angeles
(3,  3),   -- SkyDrop Deliveries  -> Chicago
(4,  4),   -- GreenWheel Scooters -> Houston
(5,  5),   -- Cafe Bonjour        -> Miami
(16, 6),   -- FreshMart Supermarkets -> Toronto
(17, 7),   -- GoClean Energy         -> Vancouver
(18, 8),   -- Metro Electronics       -> Montreal
(19, 9),   -- VeloCity Bikes          -> Ottawa
(20, 10);  -- HappyPets Store         -> Calgary


INSERT INTO CatalogItems (MerchantId, Sku, Name, WeightKg, LengthCm, WidthCm, HeightCm, HazardClass)
VALUES

(1,  N'UFF-APL-1KG', N'Apples 1kg Pack',   1.00, 25.0, 20.0, 10.0, N'None'),
(1,  N'UFF-MLK-1L',  N'Organic Milk 1L',   1.05, 8.0,  8.0,  25.0, N'Fragile'),
(1,  N'UFF-BRD-800', N'Wholegrain Bread',  0.80, 30.0, 12.0, 10.0, N'None'),

(2,  N'CRM-BATT-48V', N'48V Scooter Battery', 6.20, 30.0, 15.0, 10.0, N'Battery'),
(2,  N'CRM-TIRE-10',  N'10 Inch Street Tire', 1.10, 26.0, 26.0, 8.0,  N'None'),
(2,  N'CRM-BRKPAD',   N'Disc Brake Pads',     0.20, 10.0, 8.0,  2.0,  N'None'),


(3,  N'SDD-PROP-9IN', N'9 Inch Carbon Props', 0.15, 25.0, 5.0, 3.0,  N'None'),
(3,  N'SDD-CTRL-UNI', N'Universal Flight Ctrl',0.60, 12.0, 10.0, 4.0, N'Fragile'),
(3,  N'SDD-BATT-6S',  N'6S LiPo Battery 10Ah', 1.25, 18.0, 8.0,  7.0, N'Battery'),

(4,  N'GWS-HELM-M',  N'Safety Helmet M',  0.45, 25.0, 22.0, 20.0, N'None'),
(4,  N'GWS-LOCK-U',  N'U-Lock Hardened',  1.30, 20.0, 15.0, 3.0,  N'None'),
(4,  N'GWS-LIGHT-R', N'Rear LED Light',   0.10, 8.0,  4.0,  3.0,  N'None'),

(5,  N'CB-CFE-500', N'Roasted Coffee 500g', 0.50, 12.0, 8.0,  20.0, N'None'),
(5,  N'CB-MUG-STD', N'Ceramic Mug',         0.30, 10.0, 10.0, 10.0, N'Fragile'),
(5,  N'CB-TEA-50',  N'Herbal Tea 50 Bags',  0.25, 15.0, 10.0, 5.0,  N'None'),

(6,  N'FMS-RICE-5',  N'Basmati Rice 5kg',   5.00, 40.0, 30.0, 12.0, N'None'),
(6,  N'FMS-OIL-1L',  N'Canola Oil 1L',      0.95, 8.0,  8.0,  25.0, N'Fragile'),
(6,  N'FMS-SALT-1',  N'Iodized Salt 1kg',   1.00, 15.0, 10.0, 4.0,  N'None'),

(7,  N'GCE-CHG-500W', N'500W Smart Charger', 1.80, 22.0, 14.0, 8.0,  N'None'),
(7,  N'GCE-BATT-52V', N'52V Pack 14Ah',      3.50, 28.0, 12.0, 9.0,  N'Battery'),
(7,  N'GCE-CBL-FAST', N'Fast Charge Cable',  0.20, 18.0, 8.0,  3.0,  N'None'),

(8,  N'ME-PWRBANK', N'Power Bank 20k mAh', 0.45, 15.0, 7.0, 2.0,  N'Battery'),
(8,  N'ME-CAM-ACT', N'Action Camera 4K',   0.35, 10.0, 6.0, 4.0,  N'Fragile'),
(8,  N'ME-MEM-128', N'MicroSD 128GB',      0.02, 2.0,  2.0,  0.3, N'None'),


(9,  N'VCB-TUBE-700', N'700c Inner Tube', 0.20, 12.0, 10.0, 3.0,  N'None'),
(9,  N'VCB-CHAIN-11', N'11-Speed Chain',  0.30, 25.0, 10.0, 3.0,  N'None'),
(9,  N'VCB-LUBE-50',  N'Chain Lube 50ml', 0.10, 8.0,  3.0,  3.0,  N'None'),

(10, N'HPS-FOOD-2', N'Dry Pet Food 2kg',   2.00, 30.0, 20.0, 12.0, N'None'),
(10, N'HPS-TOY-BL', N'Rubber Ball Toy',    0.15, 8.0,  8.0,  8.0,  N'None'),
(10, N'HPS-BOWL-S', N'Stainless Bowl S',   0.25, 15.0, 15.0, 6.0,  N'None');


/* =========================
   BILLING.CUSTOMERS 
   ========================= */
INSERT INTO Customers (PersonId, OrganizationId, DefaultCurrency)
VALUES
-- Person customers (1–20)
(1,  NULL, 'USD'),
(2,  NULL, 'USD'),
(3,  NULL, 'USD'),
(4,  NULL, 'USD'),
(5,  NULL, 'USD'),
(6,  NULL, 'CAD'),
(7,  NULL, 'CAD'),
(8,  NULL, 'CAD'),
(9,  NULL, 'CAD'),
(10, NULL, 'CAD'),
(11, NULL, 'GBP'),
(12, NULL, 'GBP'),
(13, NULL, 'GBP'),
(14, NULL, 'GBP'),
(15, NULL, 'GBP'),
(16, NULL, 'EUR'),
(17, NULL, 'EUR'),
(18, NULL, 'EUR'),
(19, NULL, 'EUR'),
(20, NULL, 'EUR'),
-- Organization customers 
(NULL, 1,  'USD'),
(NULL, 2,  'USD'),
(NULL, 3,  'USD'),
(NULL, 4,  'USD'),
(NULL, 5,  'USD'),
(NULL, 16, 'CAD'),
(NULL, 17, 'CAD'),
(NULL, 18, 'CAD'),
(NULL, 19, 'CAD'),
(NULL, 20, 'CAD');


INSERT INTO Invoices (CustomerId, InvoiceNumber, Status, Currency, IssueDate, DueDate)
VALUES
(1,  N'INV-0001', N'Paid', 'USD', '2025-09-01', '2025-09-08'),
(2,  N'INV-0002', N'Paid', 'USD', '2025-09-02', '2025-09-09'),
(3,  N'INV-0003', N'Paid', 'USD', '2025-09-03', '2025-09-10'),
(4,  N'INV-0004', N'Open', 'USD', '2025-09-04', '2025-09-11'),
(5,  N'INV-0005', N'Open', 'USD', '2025-09-05', '2025-09-12'),

(6,  N'INV-0006', N'Paid', 'CAD', '2025-09-01', '2025-09-15'),
(7,  N'INV-0007', N'Paid', 'CAD', '2025-09-02', '2025-09-16'),
(8,  N'INV-0008', N'Open', 'CAD', '2025-09-03', '2025-09-17'),
(9,  N'INV-0009', N'Paid', 'CAD', '2025-09-04', '2025-09-18'),
(10, N'INV-0010', N'Open', 'CAD', '2025-09-05', '2025-09-19'),

(11, N'INV-0011', N'Paid',   'GBP', '2025-09-06', '2025-09-13'),
(12, N'INV-0012', N'Open',   'GBP', '2025-09-07', '2025-09-14'),
(13, N'INV-0013', N'Paid',   'GBP', '2025-09-08', '2025-09-15'),
(14, N'INV-0014', N'Open',   'GBP', '2025-09-09', '2025-09-16'),
(15, N'INV-0015', N'Paid',   'GBP', '2025-09-10', '2025-09-17'),

(16, N'INV-0016', N'Paid',   'EUR', '2025-09-01', '2025-09-08'),
(17, N'INV-0017', N'Open',   'EUR', '2025-09-02', '2025-09-09'),
(18, N'INV-0018', N'Paid',   'EUR', '2025-09-03', '2025-09-10'),
(19, N'INV-0019', N'Open',   'EUR', '2025-09-04', '2025-09-11'),
(20, N'INV-0020', N'Paid', 'EUR', '2025-09-05', '2025-09-12'); 
SELECT * FROM Invoices;

INSERT INTO dbo.InvoiceLines (InvoiceId, Description, Quantity, UnitPrice, TaxRatePct)
VALUES
(1,  N'Base delivery fee', 1, 100.00, 8.50),
(3,  N'Base delivery fee', 1, 100.00, 8.50),
(3,  N'Base delivery fee', 1, 100.00, 8.50),
(4,  N'Base delivery fee', 1, 100.00, 8.50),
(5,  N'Base delivery fee', 1, 100.00, 8.50),

(4,  N'Base delivery fee', 1, 120.00, 13.00),
(4,  N'Base delivery fee', 1, 120.00, 13.00),
(3,  N'Base delivery fee', 1, 120.00, 13.00),
(3,  N'Base delivery fee', 1, 120.00, 13.00),
(2, N'Base delivery fee', 1, 120.00, 13.00),

(11, N'Base delivery fee', 1, 80.00, 20.00),
(12, N'Base delivery fee', 1, 80.00, 20.00),
(13, N'Base delivery fee', 1, 80.00, 20.00),
(14, N'Base delivery fee', 1, 80.00, 20.00),
(15, N'Base delivery fee', 1, 80.00, 20.00),

(16, N'Base delivery fee', 1, 90.00, 21.00),
(17, N'Base delivery fee', 1, 90.00, 21.00),
(18, N'Base delivery fee', 1, 90.00, 21.00),
(19, N'Base delivery fee', 1, 90.00, 21.00);

INSERT INTO dbo.Payments (InvoiceId, Amount, Method, Reference)
VALUES
(1,  108.50, N'Card',   N'TXN-USD-0001'),
(2,  215.00, N'Wallet', N'TXN-USD-0002'),
(3,  150.75, N'Wire',   N'TXN-USD-0003'),
(4,  99.99,  N'Cash',   N'TXN-USD-0004'),
(5,  120.00, N'Card',   N'TXN-USD-0005'),

(6,  135.60, N'Wallet', N'TXN-CAD-0006'),
(7,  200.00, N'Wire',   N'TXN-CAD-0007'),
(8,  145.25, N'Cash',   N'TXN-CAD-0008'),
(9,  310.00, N'Card',   N'TXN-CAD-0009'),
(10,  89.99, N'Wallet', N'TXN-CAD-0010'),

(11, 96.00,  N'Wire',   N'TXN-GBP-0011'),
(12, 75.50,  N'Cash',   N'TXN-GBP-0012'),
(13, 180.40, N'Card',   N'TXN-GBP-0013'),
(14, 200.00, N'Wallet', N'TXN-GBP-0014'),
(15,  99.95, N'Wire',   N'TXN-GBP-0015'),

(16, 108.90, N'Cash',   N'TXN-EUR-0016'),
(17, 220.00, N'Card',   N'TXN-EUR-0017'),
(18, 145.75, N'Wallet', N'TXN-EUR-0018'),
(19, 300.00, N'Wire',   N'TXN-EUR-0019'),
(20,  85.20, N'Cash',   N'TXN-EUR-0020');


/* =========================
   DELIVERY: orders, packages, routing
   ========================= */

INSERT INTO dbo.Orders (MerchantId, CustomerId, CityId, PickupAddressId, DropoffAddressId, Status, Notes)
VALUES
(1,  1,  1,  1,  11, N'Pending',   N'Order 1'),
(2,  2,  2,  2,  12, N'Assigned',  N'Order 2'),
(3,  3,  3,  3,  13, N'InTransit', N'Order 3'),
(4,  4,  4,  4,  14, N'Delivered', N'Order 4'),
(5,  5,  5,  5,  15, N'Pending',   N'Order 5'),
(6,  6,  6,  6,  16, N'Assigned',  N'Order 6'),
(7,  7,  7,  7,  17, N'InTransit', N'Order 7'),
(8,  8,  8,  8,  18, N'Delivered', N'Order 8'),
(9,  9,  9,  9,  19, N'Pending',   N'Order 9'),
(10, 10, 10, 10, 20, N'Assigned',  N'Order 10'),
(1,  11, 11, 11, 21, N'InTransit', N'Order 11'),
(2,  12, 12, 12, 22, N'Delivered', N'Order 12'),
(3,  13, 13, 13, 23, N'Pending',   N'Order 13'),
(4,  14, 14, 14, 24, N'Assigned',  N'Order 14'),
(5,  15, 15, 15, 25, N'InTransit', N'Order 15'),
(6,  16, 16, 16, 26, N'Delivered', N'Order 16'),
(7,  17, 17, 17, 27, N'Pending',   N'Order 17'),
(8,  18, 18, 18, 28, N'Assigned',  N'Order 18'),
(9,  19, 19, 19, 29, N'InTransit', N'Order 19'),
(10, 20, 20, 20, 30, N'Delivered', N'Order 20');


INSERT INTO dbo.OrderItems (OrderId, CatalogItemId, Quantity, DeclaredValue)
VALUES
(1, 1,  1,  25.00),
(2, 2,  2,  60.00),
(3, 3,  1,  35.00),
(4, 4,  1, 120.00),
(5, 5,  3,  45.00),
(6, 6,  1, 135.60),
(7, 7,  2, 200.00),
(8, 8,  1, 145.25),
(9, 9,  1, 310.00),
(10,10, 1,  89.99),
(11,11, 1,  96.00),
(12,12, 2, 150.00),
(13,13, 1, 180.40),
(14,14, 1, 200.00),
(15,15, 1,  99.95),
(16,16, 1, 108.90),
(17,17, 2, 220.00),
(18,18, 1, 145.75),
(19,19, 1, 300.00),
(20,20, 1,  85.20);

-- Packages (unique LabelCode; one per order)
INSERT INTO dbo.Packages (OrderId, LabelCode, WeightKg, HazardClass)
VALUES
(1,  N'PKG-0001',  1.200, N'None'),
(2,  N'PKG-0002',  2.500, N'None'),
(3,  N'PKG-0003',  0.800, N'Fragile'),
(4,  N'PKG-0004',  6.200, N'Battery'),
(5,  N'PKG-0005',  1.000, N'None'),
(6,  N'PKG-0006',  5.000, N'None'),
(7,  N'PKG-0007',  3.500, N'Battery'),
(8,  N'PKG-0008',  0.450, N'Fragile'),
(9,  N'PKG-0009',  2.000, N'None'),
(10, N'PKG-0010',  0.300, N'None'),
(11, N'PKG-0011',  0.900, N'None'),
(12, N'PKG-0012',  1.800, N'None'),
(13, N'PKG-0013',  0.350, N'Fragile'),
(14, N'PKG-0014',  1.300, N'None'),
(15, N'PKG-0015',  2.200, N'None'),
(16, N'PKG-0016',  0.500, N'None'),
(17, N'PKG-0017',  3.800, N'None'),
(18, N'PKG-0018',  1.250, N'None'),
(19, N'PKG-0019',  2.750, N'None'),
(20, N'PKG-0020',  0.950, N'None');


INSERT INTO dbo.Routes (CityId, VehicleId, PlannedStartAt, PlannedEndAt, Status)
VALUES
(1,  1,  DATEADD(HOUR,  1, SYSDATETIME()), DATEADD(HOUR,  2, SYSDATETIME()), N'Planned'),
(2,  2,  DATEADD(HOUR,  2, SYSDATETIME()), DATEADD(HOUR,  3, SYSDATETIME()), N'Planned'),
(3,  3,  DATEADD(HOUR,  3, SYSDATETIME()), DATEADD(HOUR,  4, SYSDATETIME()), N'Planned'),
(4,  4,  DATEADD(HOUR,  4, SYSDATETIME()), DATEADD(HOUR,  5, SYSDATETIME()), N'Planned'),
(5,  5,  DATEADD(HOUR,  5, SYSDATETIME()), DATEADD(HOUR,  6, SYSDATETIME()), N'Planned'),
(6,  6,  DATEADD(HOUR,  6, SYSDATETIME()), DATEADD(HOUR,  7, SYSDATETIME()), N'Live'),
(7,  7,  DATEADD(HOUR,  7, SYSDATETIME()), DATEADD(HOUR,  8, SYSDATETIME()), N'Live'),
(8,  8,  DATEADD(HOUR,  8, SYSDATETIME()), DATEADD(HOUR,  9, SYSDATETIME()), N'Live'),
(9,  9,  DATEADD(HOUR,  9, SYSDATETIME()), DATEADD(HOUR, 10, SYSDATETIME()), N'Live'),
(10, 10, DATEADD(HOUR, 10, SYSDATETIME()), DATEADD(HOUR, 11, SYSDATETIME()), N'Live'),
(11, 11, DATEADD(HOUR, 11, SYSDATETIME()), DATEADD(HOUR, 12, SYSDATETIME()), N'Completed'),
(12, 12, DATEADD(HOUR, 12, SYSDATETIME()), DATEADD(HOUR, 13, SYSDATETIME()), N'Completed'),
(13, 13, DATEADD(HOUR, 13, SYSDATETIME()), DATEADD(HOUR, 14, SYSDATETIME()), N'Completed'),
(14, 14, DATEADD(HOUR, 14, SYSDATETIME()), DATEADD(HOUR, 15, SYSDATETIME()), N'Completed'),
(15, 15, DATEADD(HOUR, 15, SYSDATETIME()), DATEADD(HOUR, 16, SYSDATETIME()), N'Completed'),
(16, 16, DATEADD(HOUR, 16, SYSDATETIME()), DATEADD(HOUR, 17, SYSDATETIME()), N'Aborted'),
(17, 17, DATEADD(HOUR, 17, SYSDATETIME()), DATEADD(HOUR, 18, SYSDATETIME()), N'Aborted'),
(18, 18, DATEADD(HOUR, 18, SYSDATETIME()), DATEADD(HOUR, 19, SYSDATETIME()), N'Aborted'),
(19, 19, DATEADD(HOUR, 19, SYSDATETIME()), DATEADD(HOUR, 20, SYSDATETIME()), N'Aborted'),
(20, 20, DATEADD(HOUR, 20, SYSDATETIME()), DATEADD(HOUR, 21, SYSDATETIME()), N'Aborted');

-- RouteStops (one stop per route; SequenceNr unique per Route)
INSERT INTO dbo.RouteStops (RouteId, SequenceNr, AddressId, Purpose, EtaAt, EtfAt)
VALUES
(1,  1, 1,  N'Pickup',  NULL, NULL),
(2,  1, 2,  N'Pickup',  NULL, NULL),
(3,  1, 3,  N'Pickup',  NULL, NULL),
(4,  1, 4,  N'Pickup',  NULL, NULL),
(5,  1, 5,  N'Pickup',  NULL, NULL),
(6,  1, 6,  N'Pickup',  NULL, NULL),
(7,  1, 7,  N'Pickup',  NULL, NULL),
(8,  1, 8,  N'Pickup',  NULL, NULL),
(9,  1, 9,  N'Pickup',  NULL, NULL),
(10, 1, 10, N'Pickup',  NULL, NULL),
(11, 1, 11, N'Pickup',  NULL, NULL),
(12, 1, 12, N'Pickup',  NULL, NULL),
(13, 1, 13, N'Pickup',  NULL, NULL),
(14, 1, 14, N'Pickup',  NULL, NULL),
(15, 1, 15, N'Pickup',  NULL, NULL),
(16, 1, 16, N'Pickup',  NULL, NULL),
(17, 1, 17, N'Pickup',  NULL, NULL),
(18, 1, 18, N'Pickup',  NULL, NULL),
(19, 1, 19, N'Pickup',  NULL, NULL),
(20, 1, 20, N'Pickup',  NULL, NULL);

-- Assignments (link each RouteStop to matching Order and Package)
INSERT INTO dbo.Assignments (RouteStopId, OrderId, PackageId)
VALUES
(1,  1,  1),
(2,  2,  2),
(3,  3,  3),
(4,  4,  4),
(5,  5,  5),
(6,  6,  6),
(7,  7,  7),
(8,  8,  8),
(9,  9,  9),
(10, 10, 10),
(11, 11, 11),
(12, 12, 12),
(13, 13, 13),
(14, 14, 14),
(15, 15, 15),
(16, 16, 16),
(17, 17, 17),
(18, 18, 18),
(19, 19, 19),
(20, 20, 20);


INSERT INTO dbo.ProofsOfDelivery (OrderId, CapturedByUserId, Method, ArtifactUrl)
VALUES
(1,  1,  N'Signature', N'https://files/pod1'),
(2,  2,  N'Photo',     N'https://files/pod2'),
(3,  3,  N'Pin',       N'https://files/pod3'),
(4,  4,  N'Signature', N'https://files/pod4'),
(5,  5,  N'Photo',     N'https://files/pod5'),
(6,  6,  N'Pin',       N'https://files/pod6'),
(7,  7,  N'Signature', N'https://files/pod7'),
(8,  8,  N'Photo',     N'https://files/pod8'),
(9,  9,  N'Pin',       N'https://files/pod9'),
(10, 10, N'Signature', N'https://files/pod10'),
(11, 11, N'Photo',     N'https://files/pod11'),
(12, 12, N'Pin',       N'https://files/pod12'),
(13, 13, N'Signature', N'https://files/pod13'),
(14, 14, N'Photo',     N'https://files/pod14'),
(15, 15, N'Pin',       N'https://files/pod15'),
(16, 16, N'Signature', N'https://files/pod16'),
(17, 17, N'Photo',     N'https://files/pod17'),
(18, 18, N'Pin',       N'https://files/pod18'),
(19, 19, N'Signature', N'https://files/pod19'),
(20, 20, N'Photo',     N'https://files/pod20');



/* =========================
   ANALYTICS:  event firehose
   ========================= */
INSERT INTO dbo.Events (EventType, ActorUserId, EntityType, EntityIdBig, CityId, PayloadJson)
VALUES
(N'Order.Created',   1,  N'Order', 1,  1,  N'{"source":"api"}'),
(N'Order.Assigned',  2,  N'Order', 2,  2,  N'{"vehicle":5}'),
(N'Order.InTransit', 3,  N'Order', 3,  3,  N'{"eta_min":20}'),
(N'Order.Delivered', 4,  N'Order', 4,  4,  N'{"proof":"signature"}'),
(N'Order.Created',   5,  N'Order', 5,  5,  N'{}'),
(N'Route.Live',      6,  N'Route', 1,  6,  N'{"segments":10}'),
(N'Route.Live',      7,  N'Route', 2,  7,  N'{"segments":8}'),
(N'Route.Completed', 8,  N'Route', 3,  8,  N'{}'),
(N'Route.Completed', 9,  N'Route', 4,  9,  N'{}'),
(N'Route.Aborted',   10, N'Route', 5,  10, N'{"reason":"weather"}'),
(N'Order.Created',   1,  N'Order', 6,  11, N'{}'),
(N'Order.Assigned',  2,  N'Order', 7,  12, N'{}'),
(N'Order.InTransit', 3,  N'Order', 8,  13, N'{}'),
(N'Order.Delivered', 4,  N'Order', 9,  14, N'{}'),
(N'Order.Created',   5,  N'Order', 10, 15, N'{}'),
(N'Order.Created',   6,  N'Order', 11, 16, N'{}'),
(N'Order.Created',   7,  N'Order', 12, 17, N'{}'),
(N'Order.Created',   8,  N'Order', 13, 18, N'{}'),
(N'Order.Created',   9,  N'Order', 14, 19, N'{}'),
(N'Order.Created',   10, N'Order', 15, 20, N'{}');

/* =========================
   SUPPORT:  tickets and messages
   ========================= */

INSERT INTO dbo.Tickets (OpenedByUserId, RelatedOrderId, Status, Priority, Subject)
VALUES
(1,  1,  N'Open',     N'High',   N'Delay reported'),
(2,  2,  N'Pending',  N'Medium', N'Address clarification'),
(3,  NULL, N'Open',   N'Low',    N'Billing question'),
(4,  4,  N'Resolved', N'High',   N'Missing item'),
(5,  NULL, N'Open',   N'Urgent', N'Damaged package'),
(6,  6,  N'Pending',  N'Low',    N'ETA request'),
(7,  7,  N'Open',     N'High',   N'Rider behavior'),
(8,  NULL, N'Open',   N'Medium', N'Change dropoff time'),
(9,  9,  N'Pending',  N'Low',    N'Wrong label'),
(10, 10, N'Closed',   N'Low',    N'Feedback'),
(11, 11, N'Open',     N'High',   N'Route issue'),
(12, NULL, N'Pending',N'Medium', N'Invoice copy'),
(13, 13, N'Open',     N'Low',    N'Lost item'),
(14, 14, N'Resolved', N'High',   N'Late delivery'),
(15, NULL, N'Open',   N'Urgent', N'Hazard handling'),
(16, 16, N'Pending',  N'Low',    N'Proof-of-delivery'),
(17, 17, N'Open',     N'Medium', N'Custom instruction'),
(18, NULL, N'Open',   N'Low',    N'Change contact'),
(19, 19, N'Pending',  N'Medium', N'Hold request'),
(20, 20, N'Closed',   N'Low',    N'General inquiry');

INSERT INTO dbo.TicketMessages (TicketId, SenderUserId, Body)
VALUES
(1,  1,  N'We are checking with the courier.'),
(2,  2,  N'Please confirm apartment number.'),
(3,  3,  N'Billing team will follow up.'),
(4,  4,  N'Replacement initiated.'),
(5,  5,  N'Please share photos of the damage.'),
(6,  6,  N'ETA updated to 30 minutes.'),
(7,  7,  N'Thanks for reporting; coaching scheduled.'),
(8,  8,  N'Dropoff time updated.'),
(9,  9,  N'Label reprinted and attached.'),
(10, 10, N'Thanks for the feedback!'),
(11, 11, N'Route recalculated.'),
(12, 12, N'Invoice PDF emailed.'),
(13, 13, N'Search in progress.'),
(14, 14, N'Credit applied.'),
(15, 15, N'Hazard SOP shared.'),
(16, 16, N'POD attached.'),
(17, 17, N'Noted, instructions added.'),
(18, 18, N'Contact updated.'),
(19, 19, N'Order put on hold.'),
(20, 20, N'Case closed.');

 /* =========================
    AUDIT:  change history
    ========================= */
INSERT INTO dbo.ChangeLog (TableName, PrimaryKeyJson, Operation, ChangedByUserId, SnapshotJson)
VALUES
(N'Orders',        N'{"OrderId":1}',  N'INSERT', 1,  N'{}'),
(N'Orders',        N'{"OrderId":2}',  N'INSERT', 2,  N'{}'),
(N'OrderItems',    N'{"OrderItemId":1}', N'INSERT', 3,  N'{}'),
(N'Packages',      N'{"PackageId":1}', N'INSERT', 4,  N'{}'),
(N'Routes',        N'{"RouteId":1}',  N'INSERT', 5,  N'{}'),
(N'RouteStops',    N'{"RouteStopId":1}', N'INSERT', 6,  N'{}'),
(N'Assignments',   N'{"AssignmentId":1}', N'INSERT', 7,  N'{}'),
(N'ProofsOfDelivery', N'{"PodId":1}', N'INSERT', 8,  N'{}'),
(N'Events',        N'{"EventId":1}',  N'INSERT', 9,  N'{}'),
(N'Tickets',       N'{"TicketId":1}', N'INSERT', 10, N'{}'),
(N'TicketMessages',N'{"TicketMessageId":1}', N'INSERT', 1,  N'{}'),
(N'Orders',        N'{"OrderId":3}',  N'UPDATE', 2,  N'{}'),
(N'Routes',        N'{"RouteId":2}',  N'UPDATE', 3,  N'{}'),
(N'Packages',      N'{"PackageId":2}', N'UPDATE', 4,  N'{}'),
(N'Orders',        N'{"OrderId":4}',  N'DELETE', 5,  N'{}'),
(N'Events',        N'{"EventId":2}',  N'INSERT', 6,  N'{}'),
(N'Tickets',       N'{"TicketId":2}', N'UPDATE', 7,  N'{}'),
(N'TicketMessages',N'{"TicketMessageId":2}', N'INSERT', 8,  N'{}'),
(N'Assignments',   N'{"AssignmentId":2}', N'UPDATE', 9,  N'{}'),
(N'ProofsOfDelivery', N'{"PodId":2}', N'INSERT', 10, N'{}');

/*
==========================
Queries
==========================
*/
-- 1) Cities: active cities (simple where)
SELECT CityId, Name, CountryCode, TimezoneIana
FROM dbo.Cities
WHERE IsActive = 1
ORDER BY Name;

-- 2) Organizations by type
SELECT OrganizationId, Name, Type, CreatedAt
FROM dbo.Organizations
WHERE Type IN (N'Merchant', N'Partner', N'Internal')
ORDER BY CreatedAt DESC;

-- 3) Users with person info (inner join)
SELECT u.UserId, u.Username, p.FirstName, p.LastName, p.Email, u.IsLocked
FROM dbo.Users u
JOIN dbo.Persons p ON p.PersonId = u.PersonId
ORDER BY u.UserId;

-- 4) Simple text search for tickets (LIKE)
SELECT TicketId, Subject, Status, Priority
FROM dbo.Tickets
WHERE Subject LIKE N'%delivery%'  -- change keyword
ORDER BY OpenedAt DESC;


-- 5) Merchants with city and organization
SELECT m.MerchantId, o.Name AS OrganizationName, c.Name AS City
FROM dbo.Merchants m
JOIN dbo.Organizations o ON o.OrganizationId = m.OrganizationId
JOIN dbo.Cities c        ON c.CityId = m.DefaultCityId
ORDER BY m.MerchantId;

-- 6) Orders with merchant + customer + addresses
SELECT o.OrderId, o.Status,
       mer.MerchantId, org.Name AS MerchantName,
       cust.CustomerId,
       pick.Line1 AS Pickup, dropa.Line1 AS Dropoff
FROM dbo.Orders o
JOIN dbo.Merchants mer ON mer.MerchantId = o.MerchantId
JOIN dbo.Organizations org ON org.OrganizationId = mer.OrganizationId
JOIN dbo.Customers cust ON cust.CustomerId = o.CustomerId
JOIN dbo.Addresses pick ON pick.AddressId = o.PickupAddressId
JOIN dbo.Addresses dropa ON dropa.AddressId = o.DropoffAddressId
ORDER BY o.OrderId DESC;

-- 7) Invoice -> lines -> payments
SELECT i.InvoiceId, i.InvoiceNumber, i.Status, i.Currency,
       il.InvoiceLineId, il.Description, il.Quantity, il.UnitPrice, il.TaxRatePct, il.LineTotal,
       p.PaymentId, p.Amount AS PaymentAmount, p.Method
FROM dbo.Invoices i
LEFT JOIN dbo.InvoiceLines il ON il.InvoiceId = i.InvoiceId
LEFT JOIN dbo.Payments     p  ON p.InvoiceId = i.InvoiceId
ORDER BY i.InvoiceId, il.InvoiceLineId;






-- 8) Order count by status
SELECT Status, COUNT(*) AS TotalOrders
FROM dbo.Orders
GROUP BY Status
ORDER BY TotalOrders DESC;

-- 9) Revenue per invoice (sum of lines) vs paid amount
SELECT i.InvoiceId, i.InvoiceNumber,
       SUM(il.LineTotal) AS InvoiceTotal,
       COALESCE(SUM(DISTINCT p.Amount), 0) AS PaidAmount  -- if multiple payments per invoice, remove DISTINCT
FROM dbo.Invoices i
LEFT JOIN dbo.InvoiceLines il ON il.InvoiceId = i.InvoiceId
LEFT JOIN dbo.Payments     p  ON p.InvoiceId = i.InvoiceId
GROUP BY i.InvoiceId, i.InvoiceNumber
ORDER BY i.InvoiceId;

-- 10) Outstanding invoices only (InvoiceTotal > Paid)
WITH T AS (
  SELECT i.InvoiceId,
         SUM(il.LineTotal) AS InvoiceTotal,
         COALESCE(SUM(p.Amount),0) AS Paid
  FROM dbo.Invoices i
  LEFT JOIN dbo.InvoiceLines il ON il.InvoiceId = i.InvoiceId
  LEFT JOIN dbo.Payments     p  ON p.InvoiceId = i.InvoiceId
  GROUP BY i.InvoiceId
)
SELECT i.InvoiceId, i.InvoiceNumber, i.Status, i.Currency,
       T.InvoiceTotal, T.Paid, (T.InvoiceTotal - T.Paid) AS Outstanding
FROM T
JOIN dbo.Invoices i ON i.InvoiceId = T.InvoiceId
WHERE (T.InvoiceTotal - T.Paid) > 0
ORDER BY Outstanding DESC;

-- 11) Packages by hazard class
SELECT ISNULL(HazardClass, N'None') AS HazardClass, COUNT(*) AS Cnt
FROM dbo.Packages
GROUP BY HazardClass
ORDER BY Cnt DESC;




-- 12) Latest ticket message per ticket (ROW_NUMBER)
WITH M AS (
  SELECT tm.*,
         ROW_NUMBER() OVER (PARTITION BY tm.TicketId ORDER BY tm.SentAt DESC, tm.TicketMessageId DESC) AS rn
  FROM dbo.TicketMessages tm
)
SELECT TicketId, TicketMessageId, SenderUserId, SentAt, Body
FROM M
WHERE rn = 1
ORDER BY TicketId;

-- 13) Routes per city with sequence number (DENSE_RANK)
SELECT CityId, RouteId, Status,
       DENSE_RANK() OVER (PARTITION BY CityId ORDER BY RouteId) AS CityRouteSeq
FROM dbo.Routes
ORDER BY CityId, CityRouteSeq;



-- 14) Orders delivered in last 7 days
SELECT OrderId, Status, DeliveredAt
FROM dbo.Orders
WHERE Status = N'Delivered'
  AND DeliveredAt >= DATEADD(DAY, -7, SYSDATETIME())
ORDER BY DeliveredAt DESC;

-- 15) Payments received today
SELECT PaymentId, InvoiceId, Amount, Method, ReceivedAt
FROM dbo.Payments
WHERE CAST(ReceivedAt AS date) = CAST(SYSDATETIME() AS date)
ORDER BY PaymentId DESC;





-- 16) Invoices: page 2, pageSize 10 
DECLARE @PageNumber int = 2, @PageSize int = 10;
SELECT InvoiceId, InvoiceNumber, Status, IssueDate, DueDate
FROM dbo.Invoices
ORDER BY InvoiceId
OFFSET (@PageNumber - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;


-- 17) Lock a user account
UPDATE dbo.Users
SET IsLocked = 1, LastLoginAt = NULL
WHERE UserId = 5;  -- change id

-- 18) Mark invoice Paid (only if fully covered)
-- Tip: validate in application; here a quick guard using NOT EXISTS
UPDATE i
SET Status = N'Paid'
FROM dbo.Invoices i
WHERE i.InvoiceId = 10
  AND NOT EXISTS (
    SELECT 1
    FROM (
      SELECT SUM(il.LineTotal) AS Total FROM dbo.InvoiceLines il WHERE il.InvoiceId = i.InvoiceId
    ) L
    CROSS APPLY (
      SELECT COALESCE(SUM(p.Amount),0) AS Paid FROM dbo.Payments p WHERE p.InvoiceId = i.InvoiceId
    ) P
    WHERE (P.Paid < L.Total)  -- still not fully paid -> block update
  );

-- 19) Change order status to Delivered and stamp time
UPDATE dbo.Orders
SET Status = N'Delivered',
    DeliveredAt = SYSDATETIME()
WHERE OrderId = 1 AND Status IN (N'Assigned', N'InTransit');



-- 20) Delete a ticket and its messages (child first)
BEGIN TRAN;
  DELETE FROM dbo.TicketMessages WHERE TicketId = 7;
  DELETE FROM dbo.Tickets        WHERE TicketId = 7;
COMMIT TRAN;

-- 21) Delete an invoice fully (lines/payments first)
BEGIN TRAN;
  DELETE FROM dbo.Payments     WHERE InvoiceId = 15;
  DELETE FROM dbo.InvoiceLines WHERE InvoiceId = 15;
  DELETE FROM dbo.Invoices     WHERE InvoiceId = 15;
COMMIT TRAN;




-- 22) Upsert Role by name (add if missing, otherwise no-op)
MERGE dbo.Roles AS tgt
USING (SELECT N'Analyst' AS Name) AS src
ON (tgt.Name = src.Name)
WHEN NOT MATCHED THEN
  INSERT (Name) VALUES (src.Name)
WHEN MATCHED THEN
  UPDATE SET Name = src.Name;  -- trivial update
;

-- 23) Upsert Zone (CityId + Code unique)
MERGE dbo.Zones AS tgt
USING (SELECT 1 AS CityId, N'CBD' AS Code, N'Central Business District' AS Name, N'POLYGON(...)' AS PolygonWkt) AS src
ON (tgt.CityId = src.CityId AND tgt.Code = src.Code)
WHEN NOT MATCHED THEN
  INSERT (CityId, Code, Name, PolygonWkt) VALUES (src.CityId, src.Code, src.Name, src.PolygonWkt)
WHEN MATCHED THEN
  UPDATE SET Name = src.Name, PolygonWkt = src.PolygonWkt;




  -- 24) Orphan checks: InvoiceLines without parent invoice (should be zero)
SELECT il.*
FROM dbo.InvoiceLines il
LEFT JOIN dbo.Invoices i ON i.InvoiceId = il.InvoiceId
WHERE i.InvoiceId IS NULL;

-- 25) Duplicate SKUs per merchant (should be zero due to UQ)
SELECT MerchantId, Sku, COUNT(*) AS Cnt
FROM dbo.CatalogItems
GROUP BY MerchantId, Sku
HAVING COUNT(*) > 1;

-- 26) Orders whose pickup/dropoff are in different cities (sanity)
SELECT o.OrderId, o.CityId, pick.CityId AS PickupCity, dropa.CityId AS DropoffCity
FROM dbo.Orders o
JOIN dbo.Addresses pick ON pick.AddressId = o.PickupAddressId
JOIN dbo.Addresses dropa ON dropa.AddressId = o.DropoffAddressId
WHERE pick.CityId <> dropa.CityId;




-- 27) Vehicles needing maintenance (battery < 30% OR status Maintenance)
SELECT v.VehicleId, v.Type, v.Status, v.BatteryPct, h.Name AS Hub
FROM dbo.Vehicles v
JOIN dbo.Hubs h ON h.HubId = v.HubId
WHERE v.BatteryPct < 30 OR v.Status = N'Maintenance'
ORDER BY v.BatteryPct;

-- 28) Open maintenance orders with last log (if any)
WITH LastLog AS (
  SELECT ml.MaintenanceOrderId,
         MAX(ml.EntryAt) AS LastLogAt
  FROM dbo.MaintenanceLogs ml
  GROUP BY ml.MaintenanceOrderId
)
SELECT mo.MaintenanceOrderId, mo.Status, mo.Priority, v.SerialNumber, ll.LastLogAt
FROM dbo.MaintenanceOrders mo
JOIN dbo.Vehicles v ON v.VehicleId = mo.VehicleId
LEFT JOIN LastLog ll ON ll.MaintenanceOrderId = mo.MaintenanceOrderId
WHERE mo.Status IN (N'Open', N'InProgress')
ORDER BY mo.Priority DESC, mo.MaintenanceOrderId DESC;




-- 29) Recent events for orders
SELECT TOP (50) EventId, OccurredAt, EventType, EntityType, EntityIdBig, CityId
FROM dbo.Events
WHERE EntityType = N'Order'
ORDER BY OccurredAt DESC;

-- 30) ChangeLog by table (last 100)
SELECT TOP (100) ChangeId, TableName, Operation, ChangedByUserId, ChangedAt
FROM dbo.ChangeLog
ORDER BY ChangedAt DESC, ChangeId DESC;





-- A) Show foreign keys referencing a table (e.g., Invoices)
SELECT fk.name AS FK_Name, tp.name AS ChildTable, cp.name AS ChildColumn,
       tr.name AS ParentTable, cr.name AS ParentColumn
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.tables tp ON tp.object_id = fk.parent_object_id
JOIN sys.columns cp ON cp.object_id = tp.object_id AND cp.column_id = fkc.parent_column_id
JOIN sys.tables tr ON tr.object_id = fk.referenced_object_id
JOIN sys.columns cr ON cr.object_id = tr.object_id AND cr.column_id = fkc.referenced_column_id
WHERE tr.name = 'Invoices'
ORDER BY tp.name;

-- B) Quick row counts for key tables
SELECT 'Invoices' AS T, COUNT(*) AS C FROM dbo.Invoices
UNION ALL SELECT 'InvoiceLines', COUNT(*) FROM dbo.InvoiceLines
UNION ALL SELECT 'Payments', COUNT(*) FROM dbo.Payments
UNION ALL SELECT 'Orders', COUNT(*) FROM dbo.Orders
UNION ALL SELECT 'Packages', COUNT(*) FROM dbo.Packages;
